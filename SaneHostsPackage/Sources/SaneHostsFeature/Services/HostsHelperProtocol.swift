import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "HostsHelper")

// MARK: - XPC Protocol

/// Protocol defining the interface for the privileged helper tool.
/// The helper runs as a LaunchDaemon with root privileges and handles
/// operations that require elevated permissions.
@objc(HostsHelperProtocol)
public protocol HostsHelperProtocol {
    /// Writes content to /etc/hosts file
    /// - Parameters:
    ///   - content: The complete hosts file content to write
    ///   - reply: Callback with success status and optional error message
    func writeHostsFile(content: String, reply: @escaping (Bool, String?) -> Void)

    /// Flushes the DNS cache
    /// - Parameter reply: Callback with success status and optional error message
    func flushDNSCache(reply: @escaping (Bool, String?) -> Void)

    /// Gets the current /etc/hosts file content
    /// - Parameter reply: Callback with content or error message
    func readHostsFile(reply: @escaping (String?, String?) -> Void)

    /// Checks if the helper is running and responsive
    /// - Parameter reply: Callback with version string
    func getVersion(reply: @escaping (String) -> Void)
}

// MARK: - Helper Constants

public enum HostsHelperConstants {
    /// Bundle identifier for the helper tool
    public static let helperBundleID = "com.mrsane.SaneHostsHelper"

    /// Mach service name for XPC connection
    public static let machServiceName = "com.mrsane.SaneHostsHelper"

    /// Path to /etc/hosts
    public static let hostsFilePath = "/etc/hosts"

    /// Helper version
    public static let version = "1.0.0"

    /// LaunchDaemon plist filename (for SMAppService registration)
    public static let daemonPlistName = "com.mrsane.SaneHostsHelper.plist"
}

// MARK: - XPC Continuation Guard

/// Thread-safe one-shot flag to prevent double-resume of continuations.
///
/// XPC's `remoteObjectProxyWithErrorHandler` can fire the error handler
/// even after a reply handler has already been called (e.g. if the connection
/// invalidates right after a reply). Resuming a checked continuation twice
/// is undefined behavior (SIGILL). This guard ensures only the first caller wins.
private final class ContinuationGuard: @unchecked Sendable {
    private var _resumed = false
    private let lock = NSLock()

    /// Returns `true` exactly once. All subsequent calls return `false`.
    func claimResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_resumed else { return false }
        _resumed = true
        return true
    }
}

// MARK: - XPC Connection Manager

#if !APP_STORE
    /// Manages the XPC connection to the privileged helper daemon.
    public final class HostsHelperConnection: @unchecked Sendable {
        private var connection: NSXPCConnection?
        private let lock = NSLock()

        public init() {}

        private func getOrCreateConnection() -> NSXPCConnection {
            lock.lock()
            defer { lock.unlock() }
            if let existing = connection { return existing }

            let conn = NSXPCConnection(
                machServiceName: HostsHelperConstants.machServiceName,
                options: .privileged
            )
            conn.remoteObjectInterface = NSXPCInterface(with: HostsHelperProtocol.self)
            conn.invalidationHandler = { [weak self] in
                logger.info("XPC connection invalidated")
                guard let self else { return }
                lock.lock()
                connection = nil
                lock.unlock()
            }
            conn.interruptionHandler = { [weak self] in
                logger.warning("XPC connection interrupted")
                guard let self else { return }
                lock.lock()
                connection = nil
                lock.unlock()
            }
            conn.resume()
            connection = conn
            return conn
        }

        public func invalidate() {
            lock.lock()
            let conn = connection
            connection = nil
            lock.unlock()
            conn?.invalidate()
        }

        private static let xpcTimeout: TimeInterval = 5

        public func writeHostsFile(content: String) async throws {
            let conn = getOrCreateConnection()
            let (success, errorMessage): (Bool, String?) = try await withCheckedThrowingContinuation { continuation in
                let guard_ = ContinuationGuard()
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.xpcTimeout) { [weak self] in
                    guard guard_.claimResume() else { return }
                    self?.invalidate()
                    continuation.resume(throwing: HostsHelperError.connectionFailed)
                }
                let proxy = conn.remoteObjectProxyWithErrorHandler { _ in
                    guard guard_.claimResume() else { return }
                    continuation.resume(throwing: HostsHelperError.connectionFailed)
                }
                guard let helper = proxy as? HostsHelperProtocol else {
                    guard guard_.claimResume() else { return }
                    continuation.resume(throwing: HostsHelperError.connectionFailed)
                    return
                }
                helper.writeHostsFile(content: content) { success, error in
                    guard guard_.claimResume() else { return }
                    continuation.resume(returning: (success, error))
                }
            }
            guard success else {
                throw HostsHelperError.writeFailed(errorMessage ?? "Unknown error")
            }
        }

        public func flushDNSCache() async throws {
            let conn = getOrCreateConnection()
            let (success, errorMessage): (Bool, String?) = try await withCheckedThrowingContinuation { continuation in
                let guard_ = ContinuationGuard()
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.xpcTimeout) { [weak self] in
                    guard guard_.claimResume() else { return }
                    self?.invalidate()
                    continuation.resume(throwing: HostsHelperError.connectionFailed)
                }
                let proxy = conn.remoteObjectProxyWithErrorHandler { _ in
                    guard guard_.claimResume() else { return }
                    continuation.resume(throwing: HostsHelperError.connectionFailed)
                }
                guard let helper = proxy as? HostsHelperProtocol else {
                    guard guard_.claimResume() else { return }
                    continuation.resume(throwing: HostsHelperError.connectionFailed)
                    return
                }
                helper.flushDNSCache { success, error in
                    guard guard_.claimResume() else { return }
                    continuation.resume(returning: (success, error))
                }
            }
            guard success else {
                throw HostsHelperError.writeFailed(errorMessage ?? "DNS flush failed")
            }
        }

        public func isHelperRunning() async -> Bool {
            let conn = getOrCreateConnection()
            do {
                let _: String = try await withCheckedThrowingContinuation { continuation in
                    let guard_ = ContinuationGuard()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                        guard guard_.claimResume() else { return }
                        self?.invalidate()
                        continuation.resume(throwing: HostsHelperError.connectionFailed)
                    }
                    let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                        guard guard_.claimResume() else { return }
                        continuation.resume(throwing: error)
                    }
                    guard let helper = proxy as? HostsHelperProtocol else {
                        guard guard_.claimResume() else { return }
                        continuation.resume(throwing: HostsHelperError.connectionFailed)
                        return
                    }
                    helper.getVersion { version in
                        guard guard_.claimResume() else { return }
                        continuation.resume(returning: version)
                    }
                }
                return true
            } catch {
                invalidate()
                return false
            }
        }
    }
#else
    /// No-op stub — privileged XPC not available in App Store sandbox.
    /// HostsService automatically falls through to AppleScript path.
    public final class HostsHelperConnection: @unchecked Sendable {
        public init() {}
        public func invalidate() {}
        public func writeHostsFile(content _: String) async throws { throw HostsHelperError.connectionFailed }
        public func flushDNSCache() async throws { throw HostsHelperError.connectionFailed }
        public func isHelperRunning() async -> Bool { false }
    }
#endif

// MARK: - Errors

public enum HostsHelperError: LocalizedError {
    case connectionFailed
    case helperNotInstalled
    case authenticationFailed
    case writeFailed(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed:
            "Failed to connect to helper service"
        case .helperNotInstalled:
            "Helper tool is not installed"
        case .authenticationFailed:
            "Authentication failed"
        case let .writeFailed(msg):
            "Failed to write hosts file: \(msg)"
        case let .readFailed(msg):
            "Failed to read hosts file: \(msg)"
        }
    }
}

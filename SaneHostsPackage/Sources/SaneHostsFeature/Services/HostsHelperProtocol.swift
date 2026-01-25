import Foundation
import OSLog

private let logger = Logger(subsystem: "com.sanehosts.app", category: "HostsHelper")

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
}

// MARK: - XPC Connection Helper

@MainActor
public class HostsHelperConnection {

    private var connection: NSXPCConnection?

    public init() {}

    /// Gets a proxy to the helper service
    public func getHelper() throws -> HostsHelperProtocol {
        if connection == nil {
            connection = NSXPCConnection(machServiceName: HostsHelperConstants.machServiceName, options: .privileged)
            connection?.remoteObjectInterface = NSXPCInterface(with: HostsHelperProtocol.self)
            connection?.invalidationHandler = { [weak self] in
                self?.connection = nil
            }
            connection?.resume()
        }

        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
            logger.error(" XPC error: \(error.localizedDescription)")
        }) as? HostsHelperProtocol else {
            throw HostsHelperError.connectionFailed
        }

        return proxy
    }

    /// Disconnects from the helper
    public func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}

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
            return "Failed to connect to helper service"
        case .helperNotInstalled:
            return "Helper tool is not installed"
        case .authenticationFailed:
            return "Authentication failed"
        case .writeFailed(let msg):
            return "Failed to write hosts file: \(msg)"
        case .readFailed(let msg):
            return "Failed to read hosts file: \(msg)"
        }
    }
}

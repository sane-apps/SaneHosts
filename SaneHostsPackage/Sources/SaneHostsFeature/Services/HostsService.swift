import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "HostsService")

/// Reads and writes /etc/hosts. Writes go through the privileged helper
/// daemon; if it can't be reached, direct builds fall back to an
/// administrator prompt owned by the app target.
@MainActor
@Observable
public final class HostsService {
    public static let shared = HostsService()

    public private(set) var isWriting = false
    public private(set) var lastError: HostsServiceError?

    /// Tracks whether the last successful write used the XPC helper.
    /// Used to route DNS flush through the helper (root) when available.
    private var lastWriteUsedHelper = false

    /// Non-nil when the direct-build fallback already attempted DNS refresh
    /// inside the same administrator-authorized operation as the hosts write.
    private var lastFallbackDNSRefreshSucceeded: Bool?

    private let hostsPath = "/etc/hosts"
    private let parser = HostsParser()
    private let helperConnection = HostsHelperConnection()

    public init() {}

    // MARK: - Reading

    public func getSystemEntries() throws -> [HostEntry] {
        let content = try String(contentsOfFile: hostsPath, encoding: .utf8)
        return parser.extractSystemEntries(from: parser.extractEntries(from: parser.parse(content)))
    }

    /// True when the helper daemon is running, so a write needs no password prompt.
    public func canWriteWithoutPrompt() async -> Bool {
        #if DEBUG
            if AuthenticationService.debugBypassEnabled {
                return true
            }
        #endif
        return await helperConnection.isHelperRunning()
    }

    // MARK: - Writing

    /// With `interactive` false the write never falls back to a password
    /// prompt; it fails with `helperUnavailable` instead.
    public func writeHostsFile(content: String, interactive: Bool = true) async throws {
        guard !isWriting else {
            logger.warning("Write already in progress, skipping concurrent write")
            throw HostsServiceError.writeInProgress
        }

        isWriting = true
        lastError = nil
        lastWriteUsedHelper = false
        lastFallbackDNSRefreshSucceeded = nil

        defer { isWriting = false }

        #if DEBUG
            // Debug bypass - skip auth entirely in debug builds if enabled
            if AuthenticationService.debugBypassEnabled {
                logger.debug("Bypassing authentication, simulating write")
                logger.debug("Would write \(content.count) bytes to /etc/hosts")
                return
            }
        #endif

        do {
            try await writeViaHelper(content: content)
            lastWriteUsedHelper = true
            return
        } catch let error as HostsServiceError {
            // Auth-related errors (userCancelled, authenticationFailed) —
            // user already saw a dialog, do NOT fall back to AppleScript
            lastError = error
            throw error
        } catch {
            // Only fall through to the app-owned fallback if the helper was
            // unreachable BEFORE any auth dialog was shown (connectionFailed).
            if case HostsHelperError.connectionFailed = error {
                guard interactive, let fallbackWriter = HostsPrivilegedWriteFallbackRegistry.current() else {
                    let serviceError = HostsServiceError.helperUnavailable
                    lastError = serviceError
                    throw serviceError
                }
                logger.info("XPC helper unavailable, using direct-build privileged fallback")
                let result = try await fallbackWriter.writeHostsFile(content: content)
                lastFallbackDNSRefreshSucceeded = result.didRefreshDNSCache
                return
            } else {
                // Post-auth helper failure (writeFailed, etc.) —
                // user already authenticated, do NOT show another dialog
                let serviceError = HostsServiceError.writePermissionDenied(error.localizedDescription)
                lastError = serviceError
                throw serviceError
            }
        }
    }

    // MARK: - XPC Helper Path

    /// Write using the privileged helper daemon.
    ///
    /// The helper already runs as root and checks the caller is signed
    /// SaneHosts. LocalAuthentication is not repeated on this path.
    private func writeViaHelper(content: String) async throws {
        let helperAvailable = await helperConnection.isHelperRunning()
        guard helperAvailable else {
            throw HostsHelperError.connectionFailed
        }

        try await helperConnection.writeHostsFile(content: content)
        logger.info("Hosts file written via XPC helper")
    }

    // MARK: - Profile Operations

    /// - Returns: A warning when the hosts file was written but the DNS cache refresh failed.
    @discardableResult
    public func activateProfile(
        _ profile: Profile,
        systemEntries: [HostEntry],
        allowlist: HostAllowlist = HostAllowlist(),
        interactive: Bool = true
    ) async throws -> String? {
        let mergedContent = parser.merge(profile: profile, systemEntries: systemEntries, allowlist: allowlist)
        try await writeHostsFile(content: mergedContent, interactive: interactive)

        // Flush DNS cache after successful write.
        // If flush fails, the hosts file was still updated — return warning instead of throwing.
        do {
            try await flushDNSCache()
        } catch {
            let warning = "Profile activated, but DNS cache refresh did not complete: \(error.localizedDescription). Restart your browser or restart your Mac if changes are not visible yet."
            logger.warning("\(warning)")
            return warning
        }
        return nil
    }

    /// Restores hosts to system-only entries.
    /// - Returns: A warning when the hosts file was written but the DNS cache refresh failed.
    @discardableResult
    public func deactivateProfile() async throws -> String? {
        let systemEntries = try getSystemEntries()

        var lines: [String] = []
        lines.append("##")
        lines.append("# Host Database")
        lines.append("#")
        lines.append("# localhost is used to configure the loopback interface")
        lines.append("# when the system is booting.  Do not change this entry.")
        lines.append("##")

        for entry in systemEntries {
            lines.append(entry.hostsFileLine)
        }

        let content = lines.joined(separator: "\n") + "\n"
        try await writeHostsFile(content: content)

        do {
            try await flushDNSCache()
        } catch {
            let warning = "Profile deactivated, but DNS cache refresh did not complete: \(error.localizedDescription). Restart your browser or restart your Mac if changes are not visible yet."
            logger.warning("\(warning)")
            return warning
        }
        return nil
    }

    // MARK: - DNS Flush Routing

    /// Flush DNS cache using the appropriate method based on how the write was performed.
    /// - XPC path: Uses helperConnection.flushDNSCache() (runs as root, can signal mDNSResponder)
    /// - Fallback path: Reuses the DNS outcome from the same privileged operation
    ///   that wrote the hosts file, avoiding an impossible unprivileged HUP.
    /// - Debug path: Uses DNSService.shared.flushCache().
    private func flushDNSCache() async throws {
        if lastWriteUsedHelper {
            logger.info("Flushing DNS via XPC helper (root)")
            try await helperConnection.flushDNSCache()
        } else if let succeeded = lastFallbackDNSRefreshSucceeded {
            guard succeeded else {
                throw DNSServiceError.flushFailed("privileged DNS cache refresh did not complete")
            }
            logger.info("DNS was refreshed by the privileged fallback operation")
        } else {
            logger.info("Flushing DNS via DNSService")
            try await DNSService.shared.flushCache()
        }
    }
}

// MARK: - Errors

public enum HostsServiceError: LocalizedError {
    case tempFileWriteFailed(String)
    case writePermissionDenied(String)
    case readFailed(String)
    case invalidContent
    case helperUnavailable
    case authenticationFailed(String)
    case userCancelled
    case writeInProgress

    /// Returns no customer-facing message when the user dismisses macOS
    /// authentication. All real failures remain visible with action context.
    public static func actionErrorMessage(for error: Error, action: String) -> String? {
        if let serviceError = error as? HostsServiceError {
            switch serviceError {
            case .userCancelled:
                return nil
            default:
                break
            }
        }

        return "\(action): \(error.localizedDescription)"
    }

    public var errorDescription: String? {
        switch self {
        case let .tempFileWriteFailed(reason):
            return "Failed to prepare hosts file: \(reason)"
        case let .writePermissionDenied(reason):
            return "Permission denied: \(reason)"
        case let .readFailed(reason):
            return "Failed to read hosts file: \(reason)"
        case .invalidContent:
            return "Invalid hosts file content"
        case .helperUnavailable:
            return "SaneHosts couldn't reach its helper service. Reopen the app and try again."
        case let .authenticationFailed(reason):
            return "Authentication failed: \(reason)"
        case .userCancelled:
            return "Operation cancelled"
        case .writeInProgress:
            return "A write operation is already in progress. Please wait and try again."
        }
    }
}

import Foundation
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "HostsService")

/// Service for reading and writing to /etc/hosts
///
/// **Write Strategy (in order of preference):**
/// 1. **XPC Helper + Touch ID** — Privileged helper daemon writes as root.
///    User authenticates via Touch ID (LAContext). Best UX.
/// 2. **AppleScript fallback** — `do shell script with administrator privileges`.
///    Shows a password dialog (no Touch ID). Used when helper is not installed.
@MainActor
@Observable
public final class HostsService {
    public static let shared = HostsService()

    public private(set) var isWriting = false
    public private(set) var lastError: HostsServiceError?

    /// Tracks whether the last successful write used the XPC helper (true) or AppleScript (false).
    /// Used to route DNS flush through the helper (root) when available.
    private var lastWriteUsedHelper = false

    private let hostsPath = "/etc/hosts"
    private let parser = HostsParser()
    private let helperConnection = HostsHelperConnection()
    private let authService = AuthenticationService()

    public init() {}

    // MARK: - Reading

    /// Read the current system hosts file
    public func readSystemHosts() throws -> String {
        try String(contentsOfFile: hostsPath, encoding: .utf8)
    }

    /// Parse the system hosts file into entries
    public func parseSystemHosts() throws -> [HostEntry] {
        let content = try readSystemHosts()
        let lines = parser.parse(content)
        return parser.extractEntries(from: lines)
    }

    /// Extract system-critical entries (localhost, etc.)
    public func getSystemEntries() throws -> [HostEntry] {
        let entries = try parseSystemHosts()
        return parser.extractSystemEntries(from: entries)
    }

    // MARK: - Writing

    /// Write content to /etc/hosts.
    ///
    /// Tries the XPC helper (Touch ID) first. If the helper is not available,
    /// falls back to AppleScript (password dialog).
    public func writeHostsFile(content: String) async throws {
        guard !isWriting else {
            logger.warning("Write already in progress, skipping concurrent write")
            throw HostsServiceError.writeInProgress
        }

        isWriting = true
        lastError = nil

        defer { isWriting = false }

        #if DEBUG
        // Debug bypass - skip auth entirely in debug builds if enabled
        if AuthenticationService.debugBypassEnabled {
            logger.debug("Bypassing authentication, simulating write")
            logger.debug("Would write \(content.count) bytes to /etc/hosts")
            return
        }
        #endif

        // Strategy 1: XPC helper with Touch ID
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
            // Only fall through to AppleScript if the helper was unreachable
            // BEFORE any auth dialog was shown (connectionFailed).
            if case HostsHelperError.connectionFailed = error {
                logger.info("XPC helper unavailable, falling back to AppleScript")
            } else {
                // Post-auth helper failure (writeFailed, etc.) —
                // user already authenticated, do NOT show another dialog
                let serviceError = HostsServiceError.writePermissionDenied(error.localizedDescription)
                lastError = serviceError
                throw serviceError
            }
        }

        // Strategy 2: AppleScript with password dialog
        lastWriteUsedHelper = false
        try await writeViaAppleScript(content: content)
    }

    // MARK: - XPC Helper Path (Touch ID)

    /// Write using the privileged helper daemon with Touch ID authentication.
    ///
    /// Checks that the daemon is actually running BEFORE prompting for Touch ID.
    /// This avoids asking the user to authenticate only to discover the daemon
    /// is unavailable and falling back to a second password dialog.
    private func writeViaHelper(content: String) async throws {
        // Verify the helper daemon is running before asking for Touch ID
        let helperAvailable = await helperConnection.isHelperRunning()
        guard helperAvailable else {
            throw HostsHelperError.connectionFailed
        }

        // Authenticate with Touch ID / biometrics
        let authenticated = await authService.authenticate(
            reason: "SaneHosts needs to update your hosts file"
        )

        guard authenticated else {
            if case .cancelled = authService.lastError {
                throw HostsServiceError.userCancelled
            }
            throw HostsServiceError.authenticationFailed(
                authService.lastError?.localizedDescription ?? "Authentication failed"
            )
        }

        // Send write command to privileged helper via XPC
        try await helperConnection.writeHostsFile(content: content)
        logger.info("Hosts file written via XPC helper")
    }

    // MARK: - AppleScript Path (Fallback)

    /// Write using AppleScript with administrator privileges.
    /// Shows a system password dialog (no Touch ID support).
    private func writeViaAppleScript(content: String) async throws {
        // Use a fixed temp filename to avoid any path injection risk.
        // Concurrent writes are already guarded by the isWriting flag.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sanehosts-pending.hosts")

        // Remove any stale temp file from a previous failed attempt
        try? FileManager.default.removeItem(at: tempURL)

        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            let serviceError = HostsServiceError.tempFileWriteFailed(error.localizedDescription)
            lastError = serviceError
            throw serviceError
        }

        // Validate the temp path is safe for shell interpolation (defense-in-depth).
        // Our fixed path should always pass, but guard against unexpected changes.
        let tempPath = tempURL.path
        guard tempPath.allSatisfy({ $0.isASCII && !$0.isNewline }) else {
            try? FileManager.default.removeItem(at: tempURL)
            let serviceError = HostsServiceError.tempFileWriteFailed("Temp path contains unsafe characters")
            lastError = serviceError
            throw serviceError
        }

        // Build AppleScript command safely:
        // - The temp path is fully controlled (fixed filename in system temp dir)
        // - 'quoted form of' handles shell escaping for the cp command
        // - Escape \ and " for the AppleScript string literal
        let escapedPath = tempPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        do shell script "cp " & quoted form of "\(escapedPath)" & " /etc/hosts" with administrator privileges
        """

        let result = await runAppleScript(script)

        // Always clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        if !result.success {
            let serviceError = HostsServiceError.writePermissionDenied(result.error ?? "Unknown error")
            lastError = serviceError
            throw serviceError
        }
    }

    // MARK: - Profile Operations

    /// Activate a profile by writing merged hosts content
    /// - Returns: A warning message if DNS flush failed (hosts file was still written successfully)
    @discardableResult
    public func activateProfile(_ profile: Profile, systemEntries: [HostEntry]) async throws -> String? {
        let mergedContent = parser.merge(profile: profile, systemEntries: systemEntries)
        try await writeHostsFile(content: mergedContent)

        // Flush DNS cache after successful write.
        // If flush fails, the hosts file was still updated — return warning instead of throwing.
        do {
            try await flushDNSCache()
        } catch {
            let warning = "Profile activated, but DNS cache flush failed: \(error.localizedDescription). You may need to restart your browser or run 'sudo dscacheutil -flushcache' manually."
            logger.warning("\(warning)")
            return warning
        }
        return nil
    }

    /// Restore hosts to system-only entries
    /// - Returns: A warning message if DNS flush failed (hosts file was still restored successfully)
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

        // Flush DNS cache after successful write
        do {
            try await flushDNSCache()
        } catch {
            let warning = "Profile deactivated, but DNS cache flush failed: \(error.localizedDescription). You may need to restart your browser or run 'sudo dscacheutil -flushcache' manually."
            logger.warning("\(warning)")
            return warning
        }
        return nil
    }

    // MARK: - DNS Flush Routing

    /// Flush DNS cache using the appropriate method based on how the write was performed.
    /// - XPC path: Uses helperConnection.flushDNSCache() (runs as root, can signal mDNSResponder)
    /// - AppleScript path: Uses DNSService.shared.flushCache() (existing behavior)
    private func flushDNSCache() async throws {
        if lastWriteUsedHelper {
            logger.info("Flushing DNS via XPC helper (root)")
            try await helperConnection.flushDNSCache()
        } else {
            logger.info("Flushing DNS via DNSService")
            try await DNSService.shared.flushCache()
        }
    }

    // MARK: - AppleScript Execution

    private func runAppleScript(_ script: String) async -> (success: Bool, error: String?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                appleScript?.executeAndReturnError(&error)

                if let error = error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    continuation.resume(returning: (false, errorMessage))
                } else {
                    continuation.resume(returning: (true, nil))
                }
            }
        }
    }
}

// MARK: - Errors

public enum HostsServiceError: LocalizedError {
    case tempFileWriteFailed(String)
    case writePermissionDenied(String)
    case readFailed(String)
    case invalidContent
    case authenticationFailed(String)
    case userCancelled
    case writeInProgress

    public var errorDescription: String? {
        switch self {
        case .tempFileWriteFailed(let reason):
            return "Failed to prepare hosts file: \(reason)"
        case .writePermissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .readFailed(let reason):
            return "Failed to read hosts file: \(reason)"
        case .invalidContent:
            return "Invalid hosts file content"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .userCancelled:
            return "Operation cancelled"
        case .writeInProgress:
            return "A write operation is already in progress. Please wait and try again."
        }
    }
}

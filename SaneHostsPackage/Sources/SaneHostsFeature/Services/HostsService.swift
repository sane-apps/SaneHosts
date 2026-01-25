import Foundation
import AppKit
import LocalAuthentication
import OSLog

private let logger = Logger(subsystem: "com.sanehosts.app", category: "HostsService")

/// Service for reading and writing to /etc/hosts
/// Uses Touch ID for authentication, with fallback to AppleScript privilege elevation
@MainActor
@Observable
public final class HostsService {
    public static let shared = HostsService()

    public private(set) var isWriting = false
    public private(set) var lastError: HostsServiceError?

    private let hostsPath = "/etc/hosts"
    private let parser = HostsParser()
    private let authService = AuthenticationService()
    private let helperConnection = HostsHelperConnection()

    /// Whether to use Touch ID (true) or legacy AppleScript (false)
    public var useTouchID = true

    /// Whether the privileged helper is installed
    public var isHelperInstalled: Bool {
        // Check if we can connect to the helper
        // For now, return false until helper is properly installed
        #if DEBUG
        return false // Use AppleScript in debug for now
        #else
        return checkHelperInstalled()
        #endif
    }

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

    /// Write content to /etc/hosts using Touch ID or privilege elevation
    /// Returns true on success, throws on failure
    public func writeHostsFile(content: String) async throws {
        isWriting = true
        lastError = nil

        defer { isWriting = false }

        #if DEBUG
        // Debug bypass - skip auth entirely in debug builds if enabled
        if AuthenticationService.debugBypassEnabled {
            logger.debug(" Bypassing authentication, simulating write")
            // In debug mode, just print what would be written
            logger.debug(" Would write \(content.count) bytes to /etc/hosts")
            return
        }
        #endif

        // Use helper if installed (with Touch ID), otherwise fall back to AppleScript (has its own auth)
        if isHelperInstalled {
            // Touch ID auth only when using XPC helper
            if useTouchID {
                let reason = "SaneHosts needs to modify your hosts file"
                let authenticated = await authService.authenticate(reason: reason)

                if !authenticated {
                    if let error = authService.lastError {
                        if case .cancelled = error {
                            throw HostsServiceError.userCancelled
                        }
                    }
                    throw HostsServiceError.authenticationFailed(authService.lastError?.localizedDescription ?? "Unknown")
                }
            }
            try await writeViaHelper(content: content)
        } else {
            // AppleScript has its own admin password prompt - no need for Touch ID
            try await writeViaAppleScript(content: content)
        }
    }

    /// Write using the privileged helper (XPC)
    private func writeViaHelper(content: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let helper = try helperConnection.getHelper()
                helper.writeHostsFile(content: content) { success, errorMessage in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HostsServiceError.writePermissionDenied(errorMessage ?? "Unknown error"))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Write using AppleScript with administrator privileges (legacy fallback)
    private func writeViaAppleScript(content: String) async throws {
        // Write to temp file first
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sanehosts-\(UUID().uuidString).hosts")

        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            lastError = .tempFileWriteFailed(error.localizedDescription)
            throw lastError!
        }

        // Escape characters that are special in AppleScript string literals: \ and "
        // We do NOT need to escape single quotes here because we're putting it into a double-quoted AppleScript string.
        // The 'quoted form of' property in AppleScript will handle the shell escaping for us.
        let escapedPath = tempURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        // Use osascript to copy with admin privileges
        // We use 'quoted form of' to let AppleScript handle the shell escaping safely
        let script = """
        do shell script "cp " & quoted form of "\(escapedPath)" & " /etc/hosts" with administrator privileges
        """

        let result = await runAppleScript(script)

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        if !result.success {
            lastError = .writePermissionDenied(result.error ?? "Unknown error")
            throw lastError!
        }
    }

    /// Check if the privileged helper is installed and responsive
    private func checkHelperInstalled() -> Bool {
        // Try to get version from helper
        var isInstalled = false
        let semaphore = DispatchSemaphore(value: 0)

        do {
            let helper = try helperConnection.getHelper()
            helper.getVersion { _ in
                isInstalled = true
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1)
        } catch {
            isInstalled = false
        }

        return isInstalled
    }

    /// Activate a profile by writing merged hosts content
    public func activateProfile(_ profile: Profile, systemEntries: [HostEntry]) async throws {
        let mergedContent = parser.merge(profile: profile, systemEntries: systemEntries)
        try await writeHostsFile(content: mergedContent)

        // Flush DNS cache after successful write
        try await DNSService.shared.flushCache()
    }

    /// Restore hosts to system-only entries
    public func deactivateProfile() async throws {
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
        try await DNSService.shared.flushCache()
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
        }
    }
}

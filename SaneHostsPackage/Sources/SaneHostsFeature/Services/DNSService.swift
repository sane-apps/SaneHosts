import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "DNS")

/// Service for DNS cache operations
@MainActor
@Observable
public final class DNSService {
    public static let shared = DNSService()

    public private(set) var isFlushing = false
    public private(set) var lastFlushDate: Date?
    private let helperConnection = HostsHelperConnection()

    public init() {}

    /// Flush the DNS cache
    /// This ensures changes to /etc/hosts take effect immediately
    public func flushCache() async throws {
        guard !isFlushing else {
            logger.warning("DNS flush already in progress, skipping")
            return
        }

        isFlushing = true
        defer { isFlushing = false }

        if !SaneHostsBuildMode.isAppStore {
            do {
                let exitCode = try await Task.detached(priority: .userInitiated) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
                    process.arguments = ["-flushcache"]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus
                }.value

                if exitCode == 0 {
                    lastFlushDate = Date()
                    await killMDNSResponder()
                } else {
                    throw DNSServiceError.flushFailed("dscacheutil exited with code \(exitCode)")
                }
            } catch let error as DNSServiceError {
                throw error
            } catch {
                throw DNSServiceError.flushFailed(error.localizedDescription)
            }
        } else {
            do {
                try await helperConnection.flushDNSCache()
                lastFlushDate = Date()
            } catch {
                throw DNSServiceError.flushFailed("SaneHosts couldn't reach its helper service.")
            }
        }
    }

    /// Send HUP signal to mDNSResponder to force cache clear
    private func killMDNSResponder() async {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["-HUP", "mDNSResponder"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                logger.error("mDNSResponder HUP failed: \(error)")
            }
        }.value
    }

    /// Check if DNS cache was recently flushed
    public var wasRecentlyFlushed: Bool {
        guard let lastFlush = lastFlushDate else { return false }
        return Date().timeIntervalSince(lastFlush) < 60 // Within last minute
    }
}

// MARK: - Errors

public enum DNSServiceError: LocalizedError {
    case flushFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .flushFailed(reason):
            "Failed to flush DNS cache: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        "Your hosts file was updated successfully, but the DNS cache couldn't be refreshed automatically. Try restarting your browser, or run 'sudo dscacheutil -flushcache' in Terminal."
    }
}

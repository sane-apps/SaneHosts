import Foundation

/// Service for DNS cache operations
@MainActor
@Observable
public final class DNSService {
    public static let shared = DNSService()

    public private(set) var isFlushing = false
    public private(set) var lastFlushDate: Date?

    public init() {}

    /// Flush the DNS cache
    /// This ensures changes to /etc/hosts take effect immediately
    public func flushCache() async throws {
        isFlushing = true
        defer { isFlushing = false }

        // Run dscacheutil to flush DNS cache
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        process.arguments = ["-flushcache"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                lastFlushDate = Date()

                // Also send HUP to mDNSResponder for complete flush
                await killMDNSResponder()
            } else {
                throw DNSServiceError.flushFailed("dscacheutil exited with code \(process.terminationStatus)")
            }
        } catch {
            throw DNSServiceError.flushFailed(error.localizedDescription)
        }
    }

    /// Send HUP signal to mDNSResponder to force cache clear
    private func killMDNSResponder() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-HUP", "mDNSResponder"]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Non-fatal - dscacheutil already ran
            print("mDNSResponder HUP failed: \(error)")
        }
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
        case .flushFailed(let reason):
            return "Failed to flush DNS cache: \(reason)"
        }
    }
}

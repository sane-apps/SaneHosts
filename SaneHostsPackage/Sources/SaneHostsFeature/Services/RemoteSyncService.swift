import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "RemoteSync")

/// Import phase for UI tracking
public enum ImportPhase: Equatable, Sendable {
    case idle
    case connecting
    case downloading
    case parsing
    case saving
    case complete
    case error(String)
}

/// Service for fetching and syncing remote hosts files
@MainActor
@Observable
public final class RemoteSyncService {
    public static let shared = RemoteSyncService()

    public private(set) var isSyncing = false
    public private(set) var syncProgress: [URL: SyncStatus] = [:]

    /// Current import phase
    public var phase: ImportPhase = .idle
    /// Current download progress (0.0 to 1.0)
    public var downloadProgress: Double = 0
    /// Current parse progress (0.0 to 1.0)
    public var parseProgress: Double = 0
    /// Downloaded bytes
    public var downloadedBytes: Int64 = 0
    /// Total bytes expected
    public var totalBytes: Int64 = 0
    /// Status message for UI
    public var statusMessage: String = ""
    /// Whether the download total is known
    public var isIndeterminate: Bool {
        totalBytes == NSURLSessionTransferSizeUnknown || totalBytes <= 0
    }

    private let parser = HostsParser()
    private var currentTask: Task<RemoteHostsFile, Error>?

    public init() {}

    // MARK: - Public API

    /// Fetch a hosts file from a remote URL with progress tracking
    public func fetch(from url: URL) async throws -> RemoteHostsFile {
        // Enforce HTTPS for security — blocklists over HTTP can be tampered with
        if url.scheme?.lowercased() == "http" {
            throw RemoteSyncError.insecureURL
        }

        // Cancel any existing task
        currentTask?.cancel()

        syncProgress[url] = .fetching
        phase = .connecting
        downloadProgress = 0
        parseProgress = 0
        downloadedBytes = 0
        totalBytes = 0
        statusMessage = "Connecting..."

        defer {
            syncProgress.removeValue(forKey: url)
            phase = .idle
            downloadProgress = 0
            parseProgress = 0
            statusMessage = ""
        }

        do {
            // Phase 1: Download using URLSessionDownloadTask
            phase = .connecting
            let localURL = try await downloadFile(from: url)

            // Phase 2: Parse using stream (URL.lines)
            phase = .parsing
            statusMessage = "Parsing entries..."

            let result = try await parseHostsFile(at: localURL, sourceURL: url)

            phase = .complete
            statusMessage = "Found \(result.entries.count.formatted()) entries"

            // Clean up temp file
            try? FileManager.default.removeItem(at: localURL)

            return result

        } catch is CancellationError {
            throw RemoteSyncError.cancelled
        } catch let error as RemoteSyncError {
            phase = .error(error.localizedDescription)
            syncProgress[url] = .error(error.localizedDescription)
            throw error
        } catch {
            let syncError = RemoteSyncError.networkError(error.localizedDescription)
            phase = .error(syncError.localizedDescription)
            syncProgress[url] = .error(syncError.localizedDescription)
            throw syncError
        }
    }

    /// Cancel any in-progress fetch
    public func cancel() {
        currentTask?.cancel()
    }

    // MARK: - Private Download

    private func downloadFile(from url: URL) async throws -> URL {
        // SIMPLE: Just download the file, update status manually
        phase = .downloading
        statusMessage = "Downloading..."

        let (localURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error(" Response is not HTTPURLResponse")
            throw RemoteSyncError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            logger.error(" HTTP status \(httpResponse.statusCode) for \(url)")
            throw RemoteSyncError.httpError(httpResponse.statusCode)
        }

        // Move to persistent temp location
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hosts")
        try FileManager.default.moveItem(at: localURL, to: tempURL)

        downloadProgress = 1.0
        statusMessage = "Download complete"
        return tempURL
    }

    // MARK: - Private Parsing

    /// Maximum entries to import (no practical limit - UI handles display)
    private static let maxEntries = 100_000

    private func parseHostsFile(at localURL: URL, sourceURL: URL) async throws -> RemoteHostsFile {
        // First, get file size for progress estimation
        let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path)
        let fileSize = attributes?[.size] as? Int64 ?? 0

        // Estimate line count (average ~30 bytes per line for hosts files)
        let estimatedLines = max(Int(fileSize / 30), 1000)
        let maxEntries = Self.maxEntries

        // Parse on background thread using stream - DON'T store raw content
        let entries = try await Task.detached(priority: .userInitiated) { [weak self] in
            var entries: [HostEntry] = []
            entries.reserveCapacity(min(estimatedLines, maxEntries))
            let parser = HostsParser() // Hoist outside loop for performance

            var lineNumber = 0

            for try await line in localURL.lines {
                try Task.checkCancellation()

                lineNumber += 1

                // Stop if we've hit the entry limit
                if entries.count >= maxEntries {
                    await MainActor.run { [weak self] in
                        self?.statusMessage = "Limiting to \(maxEntries.formatted()) entries"
                    }
                    break
                }

                // Parse line
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

                // Parse hosts entry - supports both formats:
                // 1. Standard hosts: IP hostname [hostname2 ...]
                // 2. Domain-only: hostname (common in blocklists)
                let components = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                guard !components.isEmpty else { continue }

                var ipString: String
                var hostnames: [String]

                if components.count == 1 {
                    // Domain-only format: just a hostname
                    let domain = String(components[0])
                    // Must look like a domain (contains a dot)
                    guard domain.contains("."), parser.isValidHostname(domain) else { continue }
                    ipString = "0.0.0.0"
                    hostnames = [domain]
                } else {
                    // Standard hosts format: IP hostname [hostname2 ...]
                    ipString = String(components[0])
                    // Validate IP address format
                    guard parser.isValidIPAddress(ipString) else { continue }

                    // Extract hostnames (skip IP)
                    hostnames = components.dropFirst().compactMap { hostname -> String? in
                        let host = String(hostname)
                        // Skip localhost variations and inline comments
                        guard host != "localhost",
                              host != "localhost.localdomain",
                              host != "local",
                              host != "broadcasthost",
                              !host.hasPrefix("#") else { return nil }
                        return host
                    }
                }

                // Skip localhost variations in domain-only format too
                hostnames = hostnames.filter { host in
                    host != "localhost" &&
                        host != "localhost.localdomain" &&
                        host != "local" &&
                        host != "broadcasthost"
                }

                guard !hostnames.isEmpty else { continue }

                let entry = HostEntry(
                    id: UUID(),
                    ipAddress: ipString,
                    hostnames: hostnames,
                    isEnabled: true,
                    lineNumber: lineNumber
                )
                entries.append(entry)

                // Update progress every 1000 lines
                if lineNumber % 1000 == 0 {
                    let progress = min(Double(entries.count) / Double(maxEntries), 0.99)
                    await MainActor.run { [weak self] in
                        self?.parseProgress = progress
                        self?.statusMessage = "Parsing... \(entries.count.formatted()) entries"
                    }
                    await Task.yield() // Allow cancellation
                }
            }

            return entries
        }.value

        parseProgress = 1.0
        statusMessage = "Imported \(entries.count.formatted()) entries"

        guard !entries.isEmpty else {
            throw RemoteSyncError.noValidEntries
        }

        // Don't store raw content - it wastes memory
        return RemoteHostsFile(
            url: sourceURL,
            content: "", // Don't store raw content
            entries: entries,
            fetchedAt: Date(),
            etag: nil,
            lastModified: nil
        )
    }

    // MARK: - Fetch Multiple

    /// Fetch multiple hosts files in parallel
    public func fetchAll(urls: [URL]) async -> [URL: Result<RemoteHostsFile, Error>] {
        isSyncing = true
        defer { isSyncing = false }

        var results: [URL: Result<RemoteHostsFile, Error>] = [:]

        await withTaskGroup(of: (URL, Result<RemoteHostsFile, Error>).self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let file = try await self.fetch(from: url)
                        return (url, .success(file))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }

            for await (url, result) in group {
                results[url] = result
            }
        }

        return results
    }

    /// Check if a remote file has been updated (using ETag or Last-Modified)
    public func checkForUpdates(url: URL, etag: String?, lastModified: String?) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteSyncError.invalidResponse
        }

        // 304 Not Modified means no updates
        return httpResponse.statusCode != 304
    }
}

// MARK: - Models

/// A fetched remote hosts file
public struct RemoteHostsFile: Sendable {
    public let url: URL
    public let content: String
    public let entries: [HostEntry]
    public let fetchedAt: Date
    public let etag: String?
    public let lastModified: String?

    public var entryCount: Int { entries.count }
}

/// Sync status for a URL
public enum SyncStatus: Equatable, Sendable {
    case fetching
    case parsing
    case complete
    case error(String)
}

// MARK: - Errors

public enum RemoteSyncError: LocalizedError {
    case invalidURL
    case insecureURL
    case networkError(String)
    case httpError(Int)
    case invalidResponse
    case invalidEncoding
    case noValidEntries
    case timeout
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .insecureURL:
            "HTTPS required — blocklists over HTTP can be tampered with"
        case let .networkError(message):
            "Network error: \(message)"
        case let .httpError(code):
            "HTTP error \(code)"
        case .invalidResponse:
            "Invalid server response"
        case .invalidEncoding:
            "Could not decode file content"
        case .noValidEntries:
            "No valid hosts entries found"
        case .timeout:
            "Request timed out"
        case .cancelled:
            "Import was cancelled"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .networkError, .timeout:
            "Check your internet connection and try again"
        case .insecureURL:
            "Change the URL to use https:// instead of http://"
        case .invalidURL, .invalidResponse, .invalidEncoding, .noValidEntries:
            "Make sure the URL points to a valid hosts file"
        case .cancelled:
            nil
        case .httpError:
            "The server returned an error. Try again later."
        }
    }
}

// MARK: - Popular Hosts Lists

/// Well-known public hosts file sources
public enum PopularHostsSource: CaseIterable, Sendable {
    case stevenBlackUnified
    case stevenBlackFakenews
    case stevenBlackGambling
    case someoneWhoCares
    case mvpsHosts

    public var name: String {
        switch self {
        case .stevenBlackUnified: "Steven Black - Unified"
        case .stevenBlackFakenews: "Steven Black - Fakenews"
        case .stevenBlackGambling: "Steven Black - Gambling"
        case .someoneWhoCares: "SomeoneWhoCares"
        case .mvpsHosts: "MVPS Hosts"
        }
    }

    public var description: String {
        switch self {
        case .stevenBlackUnified:
            "Ad & malware blocking (unified hosts)"
        case .stevenBlackFakenews:
            "Fakenews site blocking"
        case .stevenBlackGambling:
            "Gambling site blocking"
        case .someoneWhoCares:
            "Ad, tracking, and malware blocking"
        case .mvpsHosts:
            "MVPS ad and tracking blocking"
        }
    }

    public var url: URL {
        switch self {
        case .stevenBlackUnified:
            URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts")!
        case .stevenBlackFakenews:
            URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts")!
        case .stevenBlackGambling:
            URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling/hosts")!
        case .someoneWhoCares:
            URL(string: "https://someonewhocares.org/hosts/hosts")!
        case .mvpsHosts:
            URL(string: "https://winhelp2002.mvps.org/hosts.txt")!
        }
    }

    public var icon: String {
        switch self {
        case .stevenBlackUnified, .stevenBlackFakenews, .stevenBlackGambling:
            "shield.fill"
        case .someoneWhoCares:
            "heart.fill"
        case .mvpsHosts:
            "checkmark.shield.fill"
        }
    }
}

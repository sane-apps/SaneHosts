import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "RemoteSync")

/// Downloads and parses blocklists from HTTPS URLs or local files.
@MainActor
public final class RemoteSyncService {
    public static let shared = RemoteSyncService()

    /// Caps disk and memory use for one list.
    static let maxDownloadBytes: Int64 = 25 * 1024 * 1024
    static let maxEntriesPerList = 500_000

    private var currentTask: Task<RemoteHostsFile, Error>?
    private var currentTaskID: UUID?
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Starting a new fetch cancels the one already running on this instance.
    public func fetch(from url: URL) async throws -> RemoteHostsFile {
        currentTask?.cancel()
        let taskID = UUID()
        currentTaskID = taskID

        let task = Task { @MainActor in
            try await self.performFetch(from: url)
        }
        currentTask = task

        defer {
            if currentTaskID == taskID {
                currentTask = nil
                currentTaskID = nil
            }
        }

        return try await task.value
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        currentTaskID = nil
    }

    private func performFetch(from url: URL) async throws -> RemoteHostsFile {
        guard url.isFileURL || Self.isAllowedRemoteURL(url) else {
            throw RemoteSyncError.insecureURL
        }

        var localCopy: URL?
        defer {
            if let localCopy {
                try? FileManager.default.removeItem(at: localCopy)
            }
        }

        do {
            let downloaded = try await download(from: url)
            localCopy = downloaded
            let entries = try await Self.parse(fileAt: downloaded)
            guard !entries.isEmpty else {
                throw RemoteSyncError.noValidEntries
            }
            return RemoteHostsFile(url: url, entries: entries, fetchedAt: Date())
        } catch is CancellationError {
            throw RemoteSyncError.cancelled
        } catch let error as RemoteSyncError {
            throw error
        } catch {
            throw RemoteSyncError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Download

    private func download(from url: URL) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hosts")

        if url.isFileURL {
            try Self.validateSize(at: url)
            try FileManager.default.copyItem(at: url, to: tempURL)
            try Self.protect(tempURL)
            return tempURL
        }

        let (downloadedURL, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Response is not HTTPURLResponse")
            throw RemoteSyncError.invalidResponse
        }
        guard let finalURL = httpResponse.url, Self.isAllowedRemoteURL(finalURL) else {
            logger.error("Remote import redirected to an insecure or unexpected transport")
            throw RemoteSyncError.insecureURL
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            logger.error("Remote import HTTP status \(httpResponse.statusCode)")
            throw RemoteSyncError.httpError(httpResponse.statusCode)
        }
        if httpResponse.expectedContentLength > Self.maxDownloadBytes {
            throw RemoteSyncError.fileTooLarge
        }

        do {
            try FileManager.default.moveItem(at: downloadedURL, to: tempURL)
            try Self.protect(tempURL)
            try Self.validateSize(at: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        return tempURL
    }

    /// Lists over plain HTTP can be tampered with; loopback is allowed for local testing.
    static func isAllowedRemoteURL(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return true
        case "http":
            let host = url.host?.lowercased()
            return host == "127.0.0.1" || host == "localhost" || host == "::1"
        default:
            return false
        }
    }

    private static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func validateSize(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? Int64 ?? 0
        guard size <= maxDownloadBytes else {
            throw RemoteSyncError.fileTooLarge
        }
    }

    // MARK: - Parsing

    private static func parse(fileAt localURL: URL) async throws -> [HostEntry] {
        let maxEntries = maxEntriesPerList
        let parseTask = Task.detached(priority: .userInitiated) { () throws -> [HostEntry] in
            let parser = HostsParser()
            var entries: [HostEntry] = []
            var lineNumber = 0

            for try await line in localURL.lines {
                lineNumber += 1
                if lineNumber % 5000 == 0 {
                    try Task.checkCancellation()
                }
                guard entries.count < maxEntries else { break }
                if let entry = parser.parseBlocklistLine(line, lineNumber: lineNumber) {
                    entries.append(entry)
                }
            }
            return entries
        }

        return try await withTaskCancellationHandler {
            try await parseTask.value
        } onCancel: {
            parseTask.cancel()
        }
    }
}

// MARK: - Models

public struct RemoteHostsFile: Sendable {
    public let url: URL
    public let entries: [HostEntry]
    public let fetchedAt: Date

    public var entryCount: Int {
        entries.count
    }
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
    case fileTooLarge
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
        case .fileTooLarge:
            "Remote hosts file is too large"
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
        case .fileTooLarge:
            "Use a smaller hosts file or split the import into smaller lists"
        case .cancelled:
            nil
        case .httpError:
            "The server returned an error. Try again later."
        }
    }
}

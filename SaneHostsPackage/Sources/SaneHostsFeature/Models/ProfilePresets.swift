import Foundation

/// Curated preset profiles for one-click protection
/// Each level includes everything from the previous level (cumulative)
public enum ProfilePreset: String, CaseIterable, Identifiable, Sendable {
    case essentials = "Essentials"
    case familySafe = "Family Safe"
    case focusMode = "Focus Mode"
    case privacyShield = "Privacy Shield"
    case kitchenSink = "Kitchen Sink"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var description: String {
        switch self {
        case .essentials:
            return "Ads, trackers, and malware. Safe for everyone."
        case .familySafe:
            return "Essentials + adult content and gambling sites."
        case .focusMode:
            return "Family Safe + social media distractions."
        case .privacyShield:
            return "Focus Mode + telemetry and advanced trackers."
        case .kitchenSink:
            return "Maximum protection. Blocks everything we can."
        }
    }

    public var tagline: String {
        switch self {
        case .essentials: return "Just make it work"
        case .familySafe: return "Protect the kids"
        case .focusMode: return "Get stuff done"
        case .privacyShield: return "Stop watching me"
        case .kitchenSink: return "Block everything we can"
        }
    }

    public var icon: String {
        switch self {
        case .essentials: return "shield.checkered"
        case .familySafe: return "figure.2.and.child.holdinghands"
        case .focusMode: return "brain.head.profile"
        case .privacyShield: return "eye.slash"
        case .kitchenSink: return "flame.fill"
        }
    }

    public var colorTag: ProfileColor {
        switch self {
        case .essentials: return .blue
        case .familySafe: return .green
        case .focusMode: return .purple
        case .privacyShield: return .pink
        case .kitchenSink: return .red
        }
    }

    /// Blocklist source IDs included in this preset (cumulative)
    public var blocklistSourceIds: [String] {
        switch self {
        case .essentials:
            return [
                "steven-black-unified",
                "hagezi-light",
                "peter-lowe"
            ]
        case .familySafe:
            return ProfilePreset.essentials.blocklistSourceIds + [
                "steven-black-porn",
                "steven-black-gambling"
            ]
        case .focusMode:
            return ProfilePreset.familySafe.blocklistSourceIds + [
                "steven-black-social",
                "tiktok-block"
            ]
        case .privacyShield:
            return ProfilePreset.focusMode.blocklistSourceIds + [
                "easyprivacy",
                "cname-cloaking",
                "windows-telemetry",
                "smart-tv"
            ]
        case .kitchenSink:
            return ProfilePreset.privacyShield.blocklistSourceIds + [
                "steven-black-fakenews",
                "fanboy-annoyances",
                "anudeep-coinminer",
                "phishing-army",
                "urlhaus"
            ]
        }
    }

    /// Get BlocklistSource objects for this preset
    public var blocklistSources: [BlocklistSource] {
        blocklistSourceIds.compactMap { id in
            BlocklistCatalog.all.first { $0.id == id }
        }
    }

    /// Estimated total entries (rough, for display)
    public var estimatedEntries: String {
        switch self {
        case .essentials: return "~170K"
        case .familySafe: return "~400K"
        case .focusMode: return "~580K"
        case .privacyShield: return "~600K"
        case .kitchenSink: return "~700K"
        }
    }

    /// Create a Profile from this preset with the given entries
    public func createProfile(with entries: [HostEntry]) -> Profile {
        Profile(
            name: displayName,
            entries: entries,
            isActive: false,
            source: .merged(sourceCount: blocklistSourceIds.count),
            colorTag: colorTag
        )
    }
}

// MARK: - Preset Manager

/// Manages preset profiles and bundled blocklist data
public actor PresetManager {
    public static let shared = PresetManager()
    private static let maxBlocklistBytes = 25 * 1024 * 1024

    /// Directory for bundled blocklist data
    private var bundledDataURL: URL? {
        Bundle.main.url(forResource: "BundledBlocklists", withExtension: nil)
    }

    /// Directory for cached/updated blocklist data
    private var cachedDataURL: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return appSupport.appendingPathComponent("SaneHosts/BlocklistCache", isDirectory: true)
    }

    /// URLSession with reasonable timeout for blocklist fetches
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Load entries for a preset, using cached data if available, otherwise bundled.
    /// Network fetches are opt-in so first launch stays local-first.
    public func loadEntries(for preset: ProfilePreset, allowNetworkFetch: Bool = true) async throws -> [HostEntry] {
        var allEntries: [HostEntry] = []

        for source in preset.blocklistSources {
            if let entries = try? await loadBlocklist(source: source, allowNetworkFetch: allowNetworkFetch) {
                allEntries.append(contentsOf: entries)
            }
        }

        // Deduplicate by hostname
        return deduplicateEntries(allEntries)
    }

    /// Load a single blocklist from cache or fetch from network
    private func loadBlocklist(source: BlocklistSource, allowNetworkFetch: Bool) async throws -> [HostEntry] {
        let cacheFile = cachedDataURL.appendingPathComponent("\(source.id).txt")
        let parser = HostsParser()

        // Try cache first
        if FileManager.default.fileExists(atPath: cacheFile.path) {
            let content = try loadLocalBlocklist(at: cacheFile)
            let lines = parser.parse(content)
            return parser.extractEntries(from: lines)
        }

        // Try bundled data
        if let bundledFile = bundledDataURL?.appendingPathComponent("\(source.id).txt"),
           FileManager.default.fileExists(atPath: bundledFile.path) {
            let content = try loadLocalBlocklist(at: bundledFile)
            let lines = parser.parse(content)
            return parser.extractEntries(from: lines)
        }

        guard allowNetworkFetch else {
            throw PresetError.networkUnavailable
        }

        // Fetch from network (with timeout)
        let content = try await fetchBlocklistContent(from: source.url)

        // Cache for future use
        try? createPrivateCacheDirectoryIfNeeded()
        try? content.write(to: cacheFile, atomically: true, encoding: .utf8)
        try? protectCacheFile(cacheFile)

        let lines = parser.parse(content)
        return parser.extractEntries(from: lines)
    }

    /// Remove duplicate hostnames, keeping first occurrence
    private func deduplicateEntries(_ entries: [HostEntry]) -> [HostEntry] {
        var seen = Set<String>()
        var unique: [HostEntry] = []

        for entry in entries {
            let key = entry.hostnames.joined(separator: ",")
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(entry)
            }
        }

        return unique
    }

    /// Update cached blocklists in background
    public func updateCachedBlocklists() async {
        for source in BlocklistCatalog.all {
            do {
                let content = try await fetchBlocklistContent(from: source.url)
                let cacheFile = cachedDataURL.appendingPathComponent("\(source.id).txt")
                try? createPrivateCacheDirectoryIfNeeded()
                try? content.write(to: cacheFile, atomically: true, encoding: .utf8)
                try? protectCacheFile(cacheFile)
            } catch {
                // Silently fail - we'll use cached/bundled data
                continue
            }
        }
    }

    private func fetchBlocklistContent(from url: URL) async throws -> String {
        let (localURL, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: localURL) }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PresetError.invalidData
        }
        guard Self.isAllowedFinalURL(httpResponse.url) else {
            throw PresetError.networkUnavailable
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw PresetError.networkUnavailable
        }
        if httpResponse.expectedContentLength > Self.maxBlocklistBytes {
            throw PresetError.fileTooLarge
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let size = attributes[.size] as? Int64 ?? 0
        guard size <= Self.maxBlocklistBytes else {
            throw PresetError.fileTooLarge
        }

        return try String(contentsOf: localURL, encoding: .utf8)
    }

    private func loadLocalBlocklist(at url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? Int64 ?? 0
        guard size <= Self.maxBlocklistBytes else {
            throw PresetError.fileTooLarge
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func isAllowedFinalURL(_ finalURL: URL?) -> Bool {
        finalURL?.scheme?.lowercased() == "https"
    }

    private func createPrivateCacheDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(
            at: cachedDataURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cachedDataURL.path)
    }

    private func protectCacheFile(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

// MARK: - Errors

public enum PresetError: Error, LocalizedError {
    case invalidData
    case networkUnavailable
    case presetNotFound
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidData: return "Invalid blocklist data"
        case .networkUnavailable: return "Network unavailable"
        case .presetNotFound: return "Preset not found"
        case .fileTooLarge: return "Blocklist file is too large"
        }
    }
}

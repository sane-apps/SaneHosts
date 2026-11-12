import Foundation

/// Curated preset profiles for one-click protection
/// Each level includes everything from the previous level (cumulative)
public enum ProfilePreset: String, CaseIterable, Identifiable, Sendable {
    case essentials = "Essentials"
    case familySafe = "Family Safe"
    case focusMode = "Focus Mode"
    case privacyShield = "Privacy Shield"
    case kitchenSink = "Kitchen Sink"

    public var id: String {
        rawValue
    }

    public var displayName: String {
        rawValue
    }

    public var description: String {
        switch self {
        case .essentials:
            "Ads, trackers, and malware. Safe for everyone."
        case .familySafe:
            "Essentials + adult content and gambling sites."
        case .focusMode:
            "Family Safe + social media distractions."
        case .privacyShield:
            "Focus Mode + telemetry and advanced trackers."
        case .kitchenSink:
            "Maximum protection. Blocks everything we can."
        }
    }

    public var tagline: String {
        switch self {
        case .essentials: "Just make it work"
        case .familySafe: "Protect the kids"
        case .focusMode: "Get stuff done"
        case .privacyShield: "Stop watching me"
        case .kitchenSink: "Block everything we can"
        }
    }

    public var icon: String {
        switch self {
        case .essentials: "shield.checkered"
        case .familySafe: "figure.2.and.child.holdinghands"
        case .focusMode: "brain.head.profile"
        case .privacyShield: "eye.slash"
        case .kitchenSink: "flame.fill"
        }
    }

    public var colorTag: ProfileColor {
        switch self {
        case .essentials: .blue
        case .familySafe: .green
        case .focusMode: .purple
        case .privacyShield: .pink
        case .kitchenSink: .red
        }
    }

    /// Blocklist source IDs included in this preset (cumulative)
    public var blocklistSourceIds: [String] {
        switch self {
        case .essentials:
            [
                "steven-black-unified",
                "hagezi-light",
                "peter-lowe"
            ]
        case .familySafe:
            ProfilePreset.essentials.blocklistSourceIds + [
                "steven-black-porn",
                "steven-black-gambling"
            ]
        case .focusMode:
            ProfilePreset.familySafe.blocklistSourceIds + [
                "steven-black-social",
                "tiktok-block"
            ]
        case .privacyShield:
            ProfilePreset.focusMode.blocklistSourceIds + [
                "easyprivacy",
                "cname-cloaking",
                "windows-telemetry",
                "smart-tv"
            ]
        case .kitchenSink:
            ProfilePreset.privacyShield.blocklistSourceIds + [
                "steven-black-fakenews",
                "wally3k",
                "crypto-jacking",
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
        case .essentials: "~230K"
        case .familySafe: "~315K"
        case .focusMode: "~320K"
        case .privacyShield: "~355K"
        case .kitchenSink: "~500K"
        }
    }

    public func createProfile(with entries: [HostEntry]) -> Profile {
        Profile(
            name: displayName,
            entries: entries,
            isActive: false,
            source: .merged(sourceCount: blocklistSourceIds.count),
            colorTag: colorTag,
            sourceURLs: blocklistSources.map(\.url),
            listsUpdatedAt: Date()
        )
    }

    public static func matching(_ profile: Profile) -> ProfilePreset? {
        guard profile.source.isMerged else { return nil }
        return allCases.first { $0.displayName.caseInsensitiveCompare(profile.name) == .orderedSame }
    }
}

// MARK: - Preset Manager

/// Loads the lists behind each preset from the local cache, the app bundle,
/// or the network, in that order.
public actor PresetManager {
    public static let shared = PresetManager()
    private static let maxBlocklistBytes = 25 * 1024 * 1024

    /// A cached list older than this is downloaded again when the network is allowed.
    static let cacheMaxAge: TimeInterval = 7 * 24 * 60 * 60

    private var bundledDataURL: URL? {
        Bundle.main.url(forResource: "BundledBlocklists", withExtension: nil)
    }

    private var cachedDataURL: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return appSupport.appendingPathComponent("SaneHosts/BlocklistCache", isDirectory: true)
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Network fetches are opt-in so first launch stays local-first.
    public func loadEntries(for preset: ProfilePreset, allowNetworkFetch: Bool = true) async throws -> [HostEntry] {
        var allEntries: [HostEntry] = []

        for source in preset.blocklistSources {
            if let entries = try? await loadBlocklist(source: source, allowNetworkFetch: allowNetworkFetch) {
                allEntries.append(contentsOf: entries)
            }
        }

        return BlocklistMerge.deduplicated(allEntries)
    }

    private func loadBlocklist(source: BlocklistSource, allowNetworkFetch: Bool) async throws -> [HostEntry] {
        let cacheFile = cachedDataURL.appendingPathComponent("\(source.id).txt")
        let parser = HostsParser()
        let cachedContent = try? loadLocalBlocklist(at: cacheFile)

        if let cachedContent, !allowNetworkFetch || !isStale(cacheFile) {
            return parser.parseBlocklist(cachedContent)
        }

        let bundledFile = bundledDataURL?.appendingPathComponent("\(source.id).txt")
        let fallbackContent = cachedContent ?? bundledFile.flatMap { try? loadLocalBlocklist(at: $0) }

        guard allowNetworkFetch else {
            if let fallbackContent {
                return parser.parseBlocklist(fallbackContent)
            }
            throw PresetError.networkUnavailable
        }

        do {
            let content = try await fetchBlocklistContent(from: source.url)
            try? createPrivateCacheDirectoryIfNeeded()
            try? content.write(to: cacheFile, atomically: true, encoding: .utf8)
            try? protectCacheFile(cacheFile)
            return parser.parseBlocklist(content)
        } catch {
            if let fallbackContent {
                return parser.parseBlocklist(fallbackContent)
            }
            throw error
        }
    }

    private func isStale(_ file: URL) -> Bool {
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        guard let modified else { return true }
        return Date().timeIntervalSince(modified) > Self.cacheMaxAge
    }

    private func fetchBlocklistContent(from url: URL) async throws -> String {
        let (localURL, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: localURL) }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PresetError.invalidData
        }
        guard Self.isAllowedFinalURL(httpResponse.url), (200 ... 299).contains(httpResponse.statusCode) else {
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
        case .invalidData: "Invalid blocklist data"
        case .networkUnavailable: "Network unavailable"
        case .presetNotFound: "Preset not found"
        case .fileTooLarge: "Blocklist file is too large"
        }
    }
}

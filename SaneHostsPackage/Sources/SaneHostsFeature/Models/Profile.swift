import Foundation

public struct Profile: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var entries: [HostEntry]
    public var isActive: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var source: ProfileSource
    public var colorTag: ProfileColor

    /// Lower values appear first in the sidebar.
    public var sortOrder: Int

    /// Blocklist URLs this profile was built from, so it can be updated later.
    /// Nil for profiles made before list updates existed.
    public var sourceURLs: [URL]?
    public var listsUpdatedAt: Date?

    /// Large profiles load with a preview of `entries`; these carry the real
    /// totals until the full file is read.
    public var entryCountOverride: Int?
    public var enabledCountOverride: Int?
    public var disabledCountOverride: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        entries: [HostEntry] = [],
        isActive: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        source: ProfileSource = .local,
        colorTag: ProfileColor = .gray,
        sortOrder: Int = 0,
        sourceURLs: [URL]? = nil,
        listsUpdatedAt: Date? = nil,
        entryCountOverride: Int? = nil,
        enabledCountOverride: Int? = nil,
        disabledCountOverride: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.isActive = isActive
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.source = source
        self.colorTag = colorTag
        self.sortOrder = sortOrder
        self.sourceURLs = sourceURLs
        self.listsUpdatedAt = listsUpdatedAt
        self.entryCountOverride = entryCountOverride
        self.enabledCountOverride = enabledCountOverride
        self.disabledCountOverride = disabledCountOverride
    }

    public var entryCount: Int {
        entryCountOverride ?? entries.count
    }

    public var hasPartialEntries: Bool {
        entryCount > entries.count
    }

    public var enabledCount: Int {
        entryCounts.enabled
    }

    public var disabledCount: Int {
        entryCounts.disabled
    }

    /// Both counts in one pass; profiles can hold 100K+ entries.
    public var entryCounts: (enabled: Int, disabled: Int) {
        if let enabledCountOverride,
           let disabledCountOverride,
           hasPartialEntries {
            return (enabledCountOverride, disabledCountOverride)
        }

        var enabled = 0
        var disabled = 0
        for entry in entries {
            if entry.isEnabled {
                enabled += 1
            } else {
                disabled += 1
            }
        }
        return (enabled, disabled)
    }

    /// Profiles saved by older versions lack the newer optional keys.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        entries = try container.decode([HostEntry].self, forKey: .entries)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        source = try container.decode(ProfileSource.self, forKey: .source)
        colorTag = try container.decode(ProfileColor.self, forKey: .colorTag)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        sourceURLs = try container.decodeIfPresent([URL].self, forKey: .sourceURLs)
        listsUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .listsUpdatedAt)
        entryCountOverride = try container.decodeIfPresent(Int.self, forKey: .entryCountOverride)
        enabledCountOverride = try container.decodeIfPresent(Int.self, forKey: .enabledCountOverride)
        disabledCountOverride = try container.decodeIfPresent(Int.self, forKey: .disabledCountOverride)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, entries, isActive, createdAt, modifiedAt, source, colorTag, sortOrder
        case sourceURLs, listsUpdatedAt
        case entryCountOverride, enabledCountOverride, disabledCountOverride
    }
}

public enum ProfileSource: Codable, Equatable, Hashable, Sendable {
    case local
    case remote(url: URL, lastFetched: Date?)
    case merged(sourceCount: Int)
    case system

    public var displayName: String {
        switch self {
        case .local: "Local"
        case let .remote(url, _): url.isFileURL ? "File" : "Remote"
        case let .merged(count): "Merged (\(count) sources)"
        case .system: "System"
        }
    }

    public var isRemote: Bool {
        if case .remote = self {
            return true
        }
        return false
    }

    public var isMerged: Bool {
        if case .merged = self {
            return true
        }
        return false
    }

    public var semanticColor: ProfileColor {
        switch self {
        case .local: .gray
        case .remote: .blue
        case .merged: .purple
        case .system: .gray
        }
    }
}

public enum ProfileColor: String, Codable, CaseIterable, Sendable {
    case gray
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink

    public var displayName: String {
        rawValue.capitalized
    }
}

public enum ProfileTemplate: CaseIterable, Sendable {
    case adBlocking
    case development
    case social
    case privacy

    public var name: String {
        switch self {
        case .adBlocking: "Ad Blocking"
        case .development: "Development"
        case .social: "Social Media Block"
        case .privacy: "Privacy"
        }
    }

    public var description: String {
        switch self {
        case .adBlocking: "Block common ad and tracking domains"
        case .development: "Local development mappings"
        case .social: "Block social media distractions"
        case .privacy: "Block telemetry and analytics"
        }
    }

    public var entries: [HostEntry] {
        switch self {
        case .adBlocking:
            [
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["ads.google.com"], comment: "Google Ads"),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["pagead2.googlesyndication.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["ad.doubleclick.net"])
            ]
        case .development:
            [
                HostEntry(ipAddress: "127.0.0.1", hostnames: ["local.dev", "api.local.dev"]),
                HostEntry(ipAddress: "127.0.0.1", hostnames: ["test.local"])
            ]
        case .social:
            [
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["facebook.com", "www.facebook.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["twitter.com", "www.twitter.com", "x.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["instagram.com", "www.instagram.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["tiktok.com", "www.tiktok.com"])
            ]
        case .privacy:
            [
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["telemetry.microsoft.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["metrics.apple.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["analytics.google.com"])
            ]
        }
    }

    public var colorTag: ProfileColor {
        switch self {
        case .adBlocking: .red
        case .development: .blue
        case .social: .purple
        case .privacy: .green
        }
    }
}

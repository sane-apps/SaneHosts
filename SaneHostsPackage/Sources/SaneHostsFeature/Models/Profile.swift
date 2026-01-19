import Foundation

/// Represents a hosts file profile that can be activated
public struct Profile: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var entries: [HostEntry]
    public var isActive: Bool
    public var createdAt: Date
    public var modifiedAt: Date

    /// Source of the profile
    public var source: ProfileSource

    /// Color tag for visual identification
    public var colorTag: ProfileColor

    /// Sort order for manual reordering (lower values appear first)
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        name: String,
        entries: [HostEntry] = [],
        isActive: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        source: ProfileSource = .local,
        colorTag: ProfileColor = .gray,
        sortOrder: Int = 0
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
    }

    /// Generate the full hosts file content for this profile
    public func generateHostsContent(preservingSystemEntries systemEntries: [HostEntry] = []) -> String {
        var lines: [String] = []

        // Add header
        lines.append("##")
        lines.append("# Host Database")
        lines.append("# Managed by SaneHosts - https://sanehosts.com")
        lines.append("# Profile: \(name)")
        lines.append("# Modified: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("##")
        lines.append("")

        // Add system entries first (localhost, broadcasthost)
        lines.append("# System entries (do not modify)")
        for entry in systemEntries {
            lines.append(entry.hostsFileLine)
        }
        lines.append("")

        // Add profile entries
        lines.append("# Profile: \(name)")
        for entry in entries where !entry.isSystemEntry {
            lines.append(entry.hostsFileLine)
        }

        return lines.joined(separator: "\n")
    }

    /// Cached entry counts - computed once per access
    /// For large profiles (100K+ entries), prefer using entryCounts computed once
    public var enabledCount: Int {
        entryCounts.enabled
    }

    /// Number of disabled entries
    public var disabledCount: Int {
        entryCounts.disabled
    }

    /// Compute both counts in single O(n) pass instead of two
    public var entryCounts: (enabled: Int, disabled: Int) {
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

    // Custom decoder to handle missing sortOrder in existing profiles
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
        // Default to 0 if sortOrder is missing (for existing profiles)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, entries, isActive, createdAt, modifiedAt, source, colorTag, sortOrder
    }
}

/// Source of a hosts profile
public enum ProfileSource: Codable, Equatable, Hashable, Sendable {
    case local
    case remote(url: URL, lastFetched: Date?)
    case merged(sourceCount: Int)
    case system

    public var displayName: String {
        switch self {
        case .local: return "Local"
        case .remote: return "Remote"
        case .merged(let count): return "Merged (\(count) sources)"
        case .system: return "System"
        }
    }

    public var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    public var isMerged: Bool {
        if case .merged = self { return true }
        return false
    }

    /// Semantic color for this source type
    public var semanticColor: ProfileColor {
        switch self {
        case .local: return .gray
        case .remote: return .blue
        case .merged: return .purple
        case .system: return .gray
        }
    }
}

/// Color tags for profiles
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

/// Predefined profile templates
public enum ProfileTemplate: CaseIterable, Sendable {
    case adBlocking
    case development
    case social
    case privacy

    public var name: String {
        switch self {
        case .adBlocking: return "Ad Blocking"
        case .development: return "Development"
        case .social: return "Social Media Block"
        case .privacy: return "Privacy"
        }
    }

    public var description: String {
        switch self {
        case .adBlocking: return "Block common ad and tracking domains"
        case .development: return "Local development mappings"
        case .social: return "Block social media distractions"
        case .privacy: return "Block telemetry and analytics"
        }
    }

    public var entries: [HostEntry] {
        switch self {
        case .adBlocking:
            return [
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["ads.google.com"], comment: "Google Ads"),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["pagead2.googlesyndication.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["ad.doubleclick.net"]),
            ]
        case .development:
            return [
                HostEntry(ipAddress: "127.0.0.1", hostnames: ["local.dev", "api.local.dev"]),
                HostEntry(ipAddress: "127.0.0.1", hostnames: ["test.local"]),
            ]
        case .social:
            return [
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["facebook.com", "www.facebook.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["twitter.com", "www.twitter.com", "x.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["instagram.com", "www.instagram.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["tiktok.com", "www.tiktok.com"]),
            ]
        case .privacy:
            return [
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["telemetry.microsoft.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["metrics.apple.com"]),
                HostEntry(ipAddress: "0.0.0.0", hostnames: ["analytics.google.com"]),
            ]
        }
    }

    public var colorTag: ProfileColor {
        switch self {
        case .adBlocking: return .red
        case .development: return .blue
        case .social: return .purple
        case .privacy: return .green
        }
    }
}

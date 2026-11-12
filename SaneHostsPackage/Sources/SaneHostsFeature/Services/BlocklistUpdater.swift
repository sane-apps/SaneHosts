import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "BlocklistUpdater")

public enum BlocklistUpdateError: LocalizedError {
    case noSources
    case sourceFailed(name: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .noSources:
            "This profile has no lists to update."
        case let .sourceFailed(name, reason):
            "Couldn’t download \(name): \(reason). Your current lists are unchanged."
        }
    }
}

public struct BlocklistUpdateResult: Sendable, Equatable {
    public let previousCount: Int
    public let newCount: Int
    public let didChange: Bool
    /// Set when the hosts file was rewritten but the DNS cache refresh failed.
    public let warning: String?
}

/// Downloads a profile's lists again and swaps in the new entries.
@MainActor
public enum BlocklistUpdater {
    /// The lists a profile can be refreshed from. Presets are found by name
    /// for profiles made before source URLs were saved.
    public static func sourceURLs(for profile: Profile) -> [URL] {
        if case let .remote(url, _) = profile.source {
            return [url]
        }
        if let urls = profile.sourceURLs, !urls.isEmpty {
            return urls
        }
        if let preset = ProfilePreset.matching(profile) {
            return preset.blocklistSources.map(\.url)
        }
        return []
    }

    public static func canUpdate(_ profile: Profile) -> Bool {
        !sourceURLs(for: profile).isEmpty
    }

    public static func lastUpdated(_ profile: Profile) -> Date? {
        if let listsUpdatedAt = profile.listsUpdatedAt {
            return listsUpdatedAt
        }
        if case let .remote(_, lastFetched) = profile.source {
            return lastFetched
        }
        return nil
    }

    /// Any failed list stops the update, so a network hiccup never leaves a
    /// profile with only part of its protection. For the active profile the
    /// hosts file is written first and the profile saved only after that
    /// succeeds, so the two never drift apart.
    public static func update(
        _ profile: Profile,
        interactive: Bool = true,
        store: ProfileStore = .shared,
        fetcher: RemoteSyncService = RemoteSyncService()
    ) async throws -> BlocklistUpdateResult {
        let urls = sourceURLs(for: profile)
        guard !urls.isEmpty else { throw BlocklistUpdateError.noSources }

        var fresh: [HostEntry] = []
        for url in urls {
            do {
                let file = try await fetcher.fetch(from: url)
                fresh.append(contentsOf: file.entries)
            } catch {
                throw BlocklistUpdateError.sourceFailed(name: displayName(for: url), reason: error.localizedDescription)
            }
        }

        let current = try await store.fullProfile(for: profile)
        let refreshedEntries = BlocklistMerge.refreshed(previous: current.entries, fresh: fresh)
        let didChange = BlocklistMerge.signature(of: refreshedEntries) != BlocklistMerge.signature(of: current.entries)

        var updated = current
        if didChange {
            updated.entries = refreshedEntries
        }
        updated.listsUpdatedAt = Date()
        if case let .remote(url, _) = current.source {
            updated.source = .remote(url: url, lastFetched: Date())
        } else if current.sourceURLs == nil {
            updated.sourceURLs = urls
        }

        var warning: String?
        if didChange, store.activeProfile?.id == current.id {
            warning = try await ProtectionController.activate(updated, interactive: interactive, requireUnlock: false, store: store)
        } else {
            try await store.save(profile: updated)
        }

        logger.info("Updated lists for \(profile.name, privacy: .public): \(current.entries.count) -> \(updated.entries.count)")
        return BlocklistUpdateResult(
            previousCount: current.entries.count,
            newCount: updated.entries.count,
            didChange: didChange,
            warning: warning
        )
    }

    static func displayName(for url: URL) -> String {
        if let source = BlocklistCatalog.all.first(where: { $0.url == url }) {
            return source.name
        }
        return url.isFileURL ? url.lastPathComponent : (url.host ?? url.absoluteString)
    }
}

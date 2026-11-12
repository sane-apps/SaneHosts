import Foundation

/// Combines blocklists into one entry list. Two entries count as the same
/// when they name the same hostnames, in any order.
public enum BlocklistMerge {
    public static let maxEntries = 500_000

    public static func key(for entry: HostEntry) -> String {
        entry.hostnames.map { $0.lowercased() }.sorted().joined(separator: ",")
    }

    /// Compares what two entry lists would write, ignoring entry IDs and order.
    public static func signature(of entries: [HostEntry]) -> Set<String> {
        Set(entries.map { "\($0.isEnabled ? "+" : "-")\($0.ipAddress) \(key(for: $0))" })
    }

    /// Keeps the first copy of each entry, up to `limit` entries.
    public static func deduplicated(_ entries: [HostEntry], limit: Int = maxEntries) -> [HostEntry] {
        var seen = Set<String>()
        var unique: [HostEntry] = []
        unique.reserveCapacity(min(entries.count, limit))

        for entry in entries {
            guard unique.count < limit else { break }
            if seen.insert(key(for: entry)).inserted {
                unique.append(entry)
            }
        }
        return unique
    }

    /// Builds the new entry list for a profile whose lists were downloaded
    /// again. Entries the user turned off stay off, and redirects the user
    /// added by hand are kept even when no list contains them. Entries that
    /// came from a list file carry a line number; hand-added ones do not, so
    /// leftovers from older imports (list headers, commented examples) drop out.
    public static func refreshed(previous: [HostEntry], fresh: [HostEntry], limit: Int = maxEntries) -> [HostEntry] {
        var disabledKeys = Set<String>()
        var customEntries: [HostEntry] = []
        for entry in previous {
            if !entry.isEnabled {
                disabledKeys.insert(key(for: entry))
            }
            if entry.lineNumber == nil,
               !HostAllowlist.blockingAddresses.contains(entry.ipAddress),
               !entry.isSystemEntry {
                customEntries.append(entry)
            }
        }

        var merged = deduplicated(customEntries + fresh, limit: limit)
        if !disabledKeys.isEmpty {
            for index in merged.indices where disabledKeys.contains(key(for: merged[index])) {
                merged[index].isEnabled = false
            }
        }
        return merged
    }
}

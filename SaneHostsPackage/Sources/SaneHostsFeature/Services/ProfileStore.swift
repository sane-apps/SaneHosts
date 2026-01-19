import Foundation
import SwiftUI

/// Notification posted when ProfileStore data changes
public extension Notification.Name {
    static let profileStoreDidChange = Notification.Name("profileStoreDidChange")
}

/// Manages profile storage and persistence
@MainActor
@Observable
public final class ProfileStore {
    // MARK: - Shared Instance

    /// Shared instance for app-wide access
    public static let shared = ProfileStore()

    /// Posts notification when data changes (for ObservableObject bridges)
    private func notifyChange() {
        NotificationCenter.default.post(name: .profileStoreDidChange, object: nil)
    }

    // MARK: - Properties

    public private(set) var profiles: [Profile] = []
    public private(set) var activeProfile: Profile?
    public private(set) var systemEntries: [HostEntry] = []
    public private(set) var isLoading = false
    public private(set) var error: ProfileStoreError?

    private let fileManager = FileManager.default
    private let parser = HostsParser()

    /// URL for storing profiles
    private var profilesDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SaneHosts/Profiles", isDirectory: true)
    }

    /// URL for the system hosts file
    private let systemHostsURL = URL(fileURLWithPath: "/etc/hosts")

    // MARK: - Initialization

    public init() {}

    // MARK: - Loading

    /// Load all profiles and system hosts
    public func load() async {
        print("[ProfileStore] load() started")
        isLoading = true
        error = nil

        do {
            // Ensure profiles directory exists
            print("[ProfileStore] Creating profiles directory...")
            try createProfilesDirectoryIfNeeded()

            // Load system hosts to extract system entries
            print("[ProfileStore] Loading system hosts...")
            try await loadSystemHosts()
            print("[ProfileStore] System hosts loaded: \(systemEntries.count) entries")

            // Load saved profiles
            print("[ProfileStore] Loading profiles...")
            try await loadProfiles()
            print("[ProfileStore] Loaded \(profiles.count) profiles")

            // First run: migrate existing user entries from /etc/hosts
            if profiles.isEmpty {
                print("[ProfileStore] First run - checking for existing user hosts entries...")
                try await migrateExistingSystemHosts()
            }

            // Create default profile if none exist (migration may have created one)
            if profiles.isEmpty {
                print("[ProfileStore] No profiles found, creating default...")
                let defaultProfile = Profile(
                    name: "Default",
                    entries: [],
                    isActive: false,
                    colorTag: .blue
                )
                profiles.append(defaultProfile)
                try await save(profile: defaultProfile)
            }
        } catch {
            print("[ProfileStore] ERROR: \(error.localizedDescription)")
            self.error = .loadFailed(error.localizedDescription)
        }

        print("[ProfileStore] load() completed, profiles: \(profiles.count)")
        isLoading = false
        notifyChange()
    }

    private func createProfilesDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: profilesDirectoryURL.path) {
            try fileManager.createDirectory(at: profilesDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func loadSystemHosts() async throws {
        let content = try String(contentsOf: systemHostsURL, encoding: .utf8)
        let lines = parser.parse(content)
        let entries = parser.extractEntries(from: lines)
        systemEntries = parser.extractSystemEntries(from: entries)
    }

    private func loadProfiles() async throws {
        let files = try fileManager.contentsOfDirectory(at: profilesDirectoryURL, includingPropertiesForKeys: nil)
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        var loadedProfiles: [Profile] = []
        for file in jsonFiles {
            let data = try Data(contentsOf: file)
            let profile = try JSONDecoder().decode(Profile.self, from: data)
            loadedProfiles.append(profile)
        }

        profiles = loadedProfiles.sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) }
        activeProfile = profiles.first { $0.isActive }
    }

    /// Migrate existing user entries from /etc/hosts on first run
    /// Creates an "Existing Entries" profile if any non-system entries are found
    private func migrateExistingSystemHosts() async throws {
        let content = try String(contentsOf: systemHostsURL, encoding: .utf8)
        let lines = parser.parse(content)
        let allEntries = parser.extractEntries(from: lines)
        let userEntries = parser.extractUserEntries(from: allEntries)

        guard !userEntries.isEmpty else {
            print("[ProfileStore] No user entries found in /etc/hosts, skipping migration")
            return
        }

        print("[ProfileStore] Found \(userEntries.count) user entries in /etc/hosts, creating backup profile...")

        let backupProfile = Profile(
            name: "Existing Entries",
            entries: userEntries,
            isActive: false,
            source: .system,
            colorTag: .orange,
            sortOrder: 0
        )

        try await save(profile: backupProfile)
        profiles.append(backupProfile)
        print("[ProfileStore] Created 'Existing Entries' profile with \(userEntries.count) entries")
    }

    // MARK: - CRUD Operations

    /// Get the next available sort order
    private var nextSortOrder: Int {
        (profiles.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Create a new profile
    public func create(name: String, from template: ProfileTemplate? = nil) async throws -> Profile {
        let profile = Profile(
            name: name,
            entries: template?.entries ?? [],
            isActive: false,
            colorTag: template?.colorTag ?? .gray,
            sortOrder: nextSortOrder
        )

        try await save(profile: profile)
        profiles.append(profile)
        profiles.sort { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) }

        return profile
    }

    /// Create a profile from a remote source
    public func createRemote(name: String, url: URL, entries: [HostEntry], maxEntries: Int = 500000) async throws -> Profile {
        // Limit entries to prevent crashes with extremely large files
        let limitedEntries = entries.count > maxEntries ? Array(entries.prefix(maxEntries)) : entries

        let profile = Profile(
            name: name,
            entries: limitedEntries,
            isActive: false,
            source: .remote(url: url, lastFetched: Date()),
            colorTag: .blue,
            sortOrder: nextSortOrder
        )

        // Save on background thread for large profiles
        let profileToSave = profile
        let fileURL = profilesDirectoryURL.appendingPathComponent("\(profileToSave.id.uuidString).json")

        try await Task.detached(priority: .userInitiated) {
            var toEncode = profileToSave
            toEncode.modifiedAt = Date()
            let data = try JSONEncoder().encode(toEncode)
            try data.write(to: fileURL, options: .atomic)
        }.value

        profiles.append(profile)
        profiles.sort { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) }

        return profile
    }

    /// Create a profile from merged sources
    public func createMerged(name: String, entries: [HostEntry], sourceCount: Int, maxEntries: Int = 500000) async throws -> Profile {
        // Limit entries to prevent crashes with extremely large files
        let limitedEntries = entries.count > maxEntries ? Array(entries.prefix(maxEntries)) : entries

        let profile = Profile(
            name: name,
            entries: limitedEntries,
            isActive: false,
            source: .merged(sourceCount: sourceCount),
            colorTag: .purple,
            sortOrder: nextSortOrder
        )

        // Save on background thread for large profiles
        let profileToSave = profile
        let fileURL = profilesDirectoryURL.appendingPathComponent("\(profileToSave.id.uuidString).json")

        try await Task.detached(priority: .userInitiated) {
            var toEncode = profileToSave
            toEncode.modifiedAt = Date()
            let data = try JSONEncoder().encode(toEncode)
            try data.write(to: fileURL, options: .atomic)
        }.value

        profiles.append(profile)
        profiles.sort { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) }

        return profile
    }

    /// Save a profile to disk
    public func save(profile: Profile) async throws {
        var updatedProfile = profile
        updatedProfile.modifiedAt = Date()

        let fileURL = profilesDirectoryURL.appendingPathComponent("\(profile.id.uuidString).json")
        let data = try JSONEncoder().encode(updatedProfile)
        try data.write(to: fileURL, options: .atomic)

        // Update in-memory list
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = updatedProfile
        }
        notifyChange()
    }

    /// Delete a profile
    public func delete(profile: Profile) async throws {
        guard !profile.isActive else {
            throw ProfileStoreError.cannotDeleteActive
        }

        let fileURL = profilesDirectoryURL.appendingPathComponent("\(profile.id.uuidString).json")
        try fileManager.removeItem(at: fileURL)

        profiles.removeAll { $0.id == profile.id }
        notifyChange()
    }

    /// Batch delete multiple profiles by ID (skips active profiles)
    /// Synchronous to avoid race conditions with UI updates
    public func deleteProfiles(ids: [UUID]) {
        let idsToRemove = Set(ids)

        // Delete files
        for id in idsToRemove {
            let fileURL = profilesDirectoryURL.appendingPathComponent("\(id.uuidString).json")
            try? fileManager.removeItem(at: fileURL)
        }

        // Remove from in-memory array in single operation
        profiles.removeAll { idsToRemove.contains($0.id) && !$0.isActive }
        notifyChange()
    }

    /// Duplicate a profile
    public func duplicate(profile: Profile) async throws -> Profile {
        let newProfile = Profile(
            id: UUID(),
            name: generateUniqueName(baseName: profile.name),
            entries: profile.entries,
            isActive: false,
            createdAt: Date(),
            modifiedAt: Date(),
            source: profile.source,
            colorTag: profile.colorTag,
            sortOrder: nextSortOrder
        )

        try await save(profile: newProfile)
        profiles.append(newProfile)
        profiles.sort { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) }

        return newProfile
    }

    /// Generate a unique name like "Default 1", "Default 2", etc.
    private func generateUniqueName(baseName: String) -> String {
        // Strip any existing " Copy" or " N" suffix to get clean base name
        let cleanBase = baseName
            .replacingOccurrences(of: #" Copy( Copy)*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression)

        let existingNames = Set(profiles.map(\.name))

        // Find first available number
        var counter = 1
        var candidateName = "\(cleanBase) \(counter)"
        while existingNames.contains(candidateName) {
            counter += 1
            candidateName = "\(cleanBase) \(counter)"
        }
        return candidateName
    }

    /// Merge multiple profiles into a new combined profile
    /// Deduplicates entries by hostname (keeps first occurrence)
    public func merge(profiles profilesToMerge: [Profile], name: String) async throws -> Profile {
        // Collect all entries, deduplicating by hostname
        var seenHostnames: Set<String> = []
        var mergedEntries: [HostEntry] = []

        for profile in profilesToMerge {
            for entry in profile.entries {
                // Create a key from all hostnames
                let hostnameKey = entry.hostnames.sorted().joined(separator: ",")
                if !seenHostnames.contains(hostnameKey) {
                    seenHostnames.insert(hostnameKey)
                    mergedEntries.append(entry)
                }
            }
        }

        let newProfile = Profile(
            id: UUID(),
            name: name,
            entries: mergedEntries,
            isActive: false,
            createdAt: Date(),
            modifiedAt: Date(),
            source: .merged(sourceCount: profilesToMerge.count),
            colorTag: .purple,
            sortOrder: nextSortOrder
        )

        try await save(profile: newProfile)
        profiles.append(newProfile)
        profiles.sort { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) }

        return newProfile
    }

    // MARK: - Reordering

    /// Move profiles from source indices to destination index
    public func moveProfiles(from source: IndexSet, to destination: Int) async throws {
        profiles.move(fromOffsets: source, toOffset: destination)

        // Reassign sort orders based on new positions
        for (index, profile) in profiles.enumerated() {
            if profile.sortOrder != index {
                var updated = profile
                updated.sortOrder = index
                try await save(profile: updated)
            }
        }
    }

    // MARK: - Activation

    /// Activate a profile (writes to /etc/hosts via helper)
    /// Returns the hosts content that should be written
    public func prepareActivation(profile: Profile) -> String {
        return parser.merge(profile: profile, systemEntries: systemEntries)
    }

    /// Mark a profile as active (after successful write)
    public func markAsActive(profile: Profile) async throws {
        // Deactivate current active profile
        if let current = activeProfile, current.id != profile.id {
            var deactivated = current
            deactivated.isActive = false
            try await save(profile: deactivated)
        }

        // Activate new profile
        var activated = profile
        activated.isActive = true
        try await save(profile: activated)

        activeProfile = activated
        notifyChange()
    }

    /// Deactivate the current profile
    public func deactivate() async throws {
        guard let current = activeProfile else { return }

        var deactivated = current
        deactivated.isActive = false
        try await save(profile: deactivated)

        activeProfile = nil
        notifyChange()
    }

    // MARK: - Entry Management

    /// Add an entry to a profile
    public func addEntry(_ entry: HostEntry, to profile: Profile) async throws {
        guard let current = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }
        var updated = current
        updated.entries.append(entry)
        try await save(profile: updated)
    }

    /// Add multiple entries to a profile (batch operation)
    /// Limits to maxEntries to prevent memory issues with extremely large hosts files
    public func addEntries(_ entries: [HostEntry], to profile: Profile, maxEntries: Int = 500000) async throws {
        guard let current = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }

        // Limit entries to prevent crashes with extremely large files
        let limitedEntries = entries.count > maxEntries ? Array(entries.prefix(maxEntries)) : entries

        var updated = current
        updated.entries.append(contentsOf: limitedEntries)

        // Perform encoding on background thread to avoid blocking UI
        let profileToSave = updated
        let fileURL = profilesDirectoryURL.appendingPathComponent("\(profileToSave.id.uuidString).json")

        try await Task.detached(priority: .userInitiated) {
            var toEncode = profileToSave
            toEncode.modifiedAt = Date()
            let data = try JSONEncoder().encode(toEncode)
            try data.write(to: fileURL, options: .atomic)
        }.value

        // Update in-memory list on main actor
        updated.modifiedAt = Date()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = updated
        }
    }

    /// Remove an entry from a profile
    public func removeEntry(_ entry: HostEntry, from profile: Profile) async throws {
        var updated = profile
        updated.entries.removeAll { $0.id == entry.id }
        try await save(profile: updated)
    }

    /// Update an entry in a profile
    public func updateEntry(_ entry: HostEntry, in profile: Profile) async throws {
        var updated = profile
        if let index = updated.entries.firstIndex(where: { $0.id == entry.id }) {
            updated.entries[index] = entry
            try await save(profile: updated)
        }
    }

    /// Toggle entry enabled state
    public func toggleEntry(_ entry: HostEntry, in profile: Profile) async throws {
        var updatedEntry = entry
        updatedEntry.isEnabled.toggle()
        try await updateEntry(updatedEntry, in: profile)
    }

    /// Bulk update entries in a profile (single disk write)
    /// - Parameters:
    ///   - ids: Set of entry IDs to update
    ///   - profile: The profile containing the entries
    ///   - update: Closure that modifies each entry in-place
    public func bulkUpdateEntries(ids: Set<UUID>, in profile: Profile, update: (inout HostEntry) -> Void) async throws {
        guard let current = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }

        var updated = current
        for i in updated.entries.indices {
            if ids.contains(updated.entries[i].id) {
                update(&updated.entries[i])
            }
        }

        try await save(profile: updated)
    }

    /// Bulk remove entries from a profile (single disk write)
    /// - Parameters:
    ///   - ids: Set of entry IDs to remove
    ///   - profile: The profile to remove entries from
    public func bulkRemoveEntries(ids: Set<UUID>, from profile: Profile) async throws {
        guard let current = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }

        var updated = current
        updated.entries.removeAll { ids.contains($0.id) }
        try await save(profile: updated)
    }

    // MARK: - Import/Export

    /// Import entries from a hosts file string
    public func importEntries(from content: String) -> [HostEntry] {
        let lines = parser.parse(content)
        return parser.extractUserEntries(from: parser.extractEntries(from: lines))
    }

    /// Export a profile as hosts file content
    public func exportProfile(_ profile: Profile) -> String {
        return parser.merge(profile: profile, systemEntries: systemEntries)
    }
}

// MARK: - Errors

public enum ProfileStoreError: LocalizedError {
    case loadFailed(String)
    case saveFailed(String)
    case cannotDeleteActive
    case profileNotFound

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let reason): return "Failed to load profiles: \(reason)"
        case .saveFailed(let reason): return "Failed to save profile: \(reason)"
        case .cannotDeleteActive: return "Cannot delete the active profile. Deactivate it first."
        case .profileNotFound: return "Profile not found"
        }
    }
}

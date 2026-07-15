import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "ProfileStore")

/// Notification posted when ProfileStore data changes
public extension Notification.Name {
    static let profileStoreDidChange = Notification.Name("profileStoreDidChange")
}

public enum ProfileStoreBootstrapPolicy {
    public static func shouldLoad(profileCount: Int, isLoading: Bool) -> Bool {
        profileCount == 0 && !isLoading
    }
}

public enum ProfileStoreEssentialsPolicy {
    public static func needsEssentialsProfile(profiles: [Profile]) -> Bool {
        !profiles.contains { $0.name.caseInsensitiveCompare(ProfilePreset.essentials.displayName) == .orderedSame }
    }
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

    /// Most recent large-profile hydration failure, kept for diagnostics
    /// reports (customer payloads previously carried no trace of these).
    /// Cleared by the next successful hydration.
    public private(set) var lastHydrationIssue: String?

    private let fileManager = FileManager.default
    private let parser = HostsParser()
    private let profilesDirectoryOverrideURL: URL?
    private let backupsDirectoryOverrideURL: URL?

    /// URL for storing profiles
    private var profilesDirectoryURL: URL {
        if let profilesDirectoryOverrideURL {
            return profilesDirectoryOverrideURL
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return appSupport.appendingPathComponent("SaneHosts/Profiles", isDirectory: true)
    }

    /// URL for profile backups (crash resilience)
    private var backupsDirectoryURL: URL {
        if let backupsDirectoryOverrideURL {
            return backupsDirectoryOverrideURL
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return appSupport.appendingPathComponent("SaneHosts/Backups", isDirectory: true)
    }

    /// URL for the system hosts file
    private let systemHostsURL: URL

    /// Maximum number of backups to keep per profile
    private let maxBackupsPerProfile = 3
    private let maxSystemHostsBytes: Int64 = 25 * 1024 * 1024
    private let largeProfilePreviewEntryLimit: Int
    private let largeProfileSummaryThresholdBytes: Int64

    // MARK: - Initialization

    public init() {
        profilesDirectoryOverrideURL = nil
        backupsDirectoryOverrideURL = nil
        systemHostsURL = URL(fileURLWithPath: "/etc/hosts")
        largeProfilePreviewEntryLimit = 100
        largeProfileSummaryThresholdBytes = 2 * 1024 * 1024
    }

    init(
        storageRootURL: URL,
        systemHostsURL: URL,
        largeProfilePreviewEntryLimit: Int = 100,
        largeProfileSummaryThresholdBytes: Int64 = 2 * 1024 * 1024
    ) {
        profilesDirectoryOverrideURL = storageRootURL.appendingPathComponent("Profiles", isDirectory: true)
        backupsDirectoryOverrideURL = storageRootURL.appendingPathComponent("Backups", isDirectory: true)
        self.systemHostsURL = systemHostsURL
        self.largeProfilePreviewEntryLimit = largeProfilePreviewEntryLimit
        self.largeProfileSummaryThresholdBytes = largeProfileSummaryThresholdBytes
    }

    // MARK: - Loading

    /// Load all profiles and system hosts
    public func load() async {
        logger.debug(" load() started")
        isLoading = true
        error = nil

        do {
            // Ensure profiles directory exists
            logger.debug(" Creating profiles directory...")
            try createProfilesDirectoryIfNeeded()

            // Load system hosts to extract system entries
            logger.debug("Loading system hosts...")
            try await loadSystemHosts()
            let sysCount = systemEntries.count
            logger.debug("System hosts loaded: \(sysCount) entries")

            // Load saved profiles
            logger.debug("Loading profiles...")
            try await loadProfiles()
            let profCount = profiles.count
            logger.debug("Loaded \(profCount) profiles")

            // First run: migrate existing user entries from /etc/hosts
            if profiles.isEmpty {
                logger.debug(" First run - checking for existing user hosts entries...")
                try await migrateExistingSystemHosts()
            }

            // Basic must always have the free Essentials profile, even when
            // first-run migration created an "Existing Entries" profile.
            if ProfileStoreEssentialsPolicy.needsEssentialsProfile(profiles: profiles) {
                logger.debug(" Essentials profile missing, creating Essentials preset...")
                await createEssentialsProfile()
            }
        } catch {
            logger.debug(" ERROR: \(error.localizedDescription)")
            self.error = .loadFailed(error.localizedDescription)
        }

        let finalCount = profiles.count
        logger.debug("load() completed, profiles: \(finalCount)")
        isLoading = false
        notifyChange()
    }

    private func createProfilesDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: profilesDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.createDirectory(
            at: backupsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try backupArchive.protectStoragePermissions()
    }

    // MARK: - Preset Profiles

    /// Create the Essentials preset profile on first launch
    private func createEssentialsProfile() async {
        logger.debug("Creating Essentials preset profile...")

        do {
            // First launch is local-first: use cached or bundled entries only.
            let entries = try await PresetManager.shared.loadEntries(for: .essentials, allowNetworkFetch: false)
            logger.debug("Loaded \(entries.count) entries for Essentials")

            let essentialsProfile = ProfilePreset.essentials.createProfile(with: entries)
            profiles.append(essentialsProfile)
            try await save(profile: essentialsProfile)

            logger.debug("Essentials profile created with \(entries.count) entries")
        } catch {
            logger.debug("Failed to load Essentials preset: \(error.localizedDescription)")
            // Fallback: create empty profile so app doesn't crash
            let fallbackProfile = Profile(
                name: "Essentials",
                entries: [],
                isActive: false,
                colorTag: .blue
            )
            profiles.append(fallbackProfile)
            try? await save(profile: fallbackProfile)
            logger.debug("Created empty fallback Essentials profile")
        }
    }

    /// Create a profile from a preset
    public func createProfile(from preset: ProfilePreset) async throws {
        logger.debug("Creating profile from preset: \(preset.displayName)")

        let entries = try await PresetManager.shared.loadEntries(for: preset)
        let profile = preset.createProfile(with: entries)

        profiles.append(profile)
        try await save(profile: profile)
        notifyChange()

        logger.debug("Created \(preset.displayName) with \(entries.count) entries")
    }

    // MARK: - Backup & Recovery

    /// Backup, recovery, and storage-permission enforcement. Computed because
    /// the storage directories can be overridden per instance for tests.
    private var backupArchive: ProfileBackupArchive {
        ProfileBackupArchive(
            profilesDirectoryURL: profilesDirectoryURL,
            backupsDirectoryURL: backupsDirectoryURL,
            maxBackupsPerProfile: maxBackupsPerProfile
        )
    }

    private func loadSystemHosts() async throws {
        let url = systemHostsURL
        let parser = parser
        try validateSystemHostsSize()

        // Only parse the system entries header, not the full 200K+ line hosts file.
        // System entries (localhost, broadcasthost) appear before the "# ---- Profile:" marker.
        let entries = try await Task.detached(priority: .userInitiated) {
            let content = try String(contentsOf: url, encoding: .utf8)

            // Extract only the header section before profile entries begin
            let headerContent: String = if let markerRange = content.range(of: "# ---- Profile:") {
                String(content[content.startIndex ..< markerRange.lowerBound])
            } else {
                // No managed section - parse the whole file (small /etc/hosts)
                content
            }

            let lines = parser.parse(headerContent)
            let allEntries = parser.extractEntries(from: lines)
            return parser.extractSystemEntries(from: allEntries)
        }.value

        systemEntries = entries
    }

    private var directoryLoader: ProfileDirectoryLoader {
        ProfileDirectoryLoader(
            profilesDirectoryURL: profilesDirectoryURL,
            backupsDirectoryURL: backupsDirectoryURL,
            largeProfilePreviewEntryLimit: largeProfilePreviewEntryLimit,
            largeProfileSummaryThresholdBytes: largeProfileSummaryThresholdBytes,
            archive: backupArchive
        )
    }

    private func loadProfiles() async throws {
        let loadedProfiles = try await directoryLoader.load { recovered in
            try? await self.save(profile: recovered)
        }

        profiles = loadedProfiles.sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) }
        activeProfile = profiles.first { $0.isActive }
    }

    public func fullProfile(for profile: Profile) async throws -> Profile {
        guard profile.hasPartialEntries else { return profile }
        let fileURL = profilesDirectoryURL.appendingPathComponent("\(profile.id.uuidString).json")
        do {
            let fullProfile = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: fileURL)
                let fullProfile = try JSONDecoder().decode(Profile.self, from: data)
                guard fullProfile.id == profile.id else {
                    throw ProfileStoreError.invalidProfileIdentity("Stored profile ID does not match its summary or filename")
                }
                return fullProfile
            }.value
            lastHydrationIssue = nil
            return fullProfile
        } catch {
            lastHydrationIssue = "Hydrating '\(profile.name)' failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Migrate existing user entries from /etc/hosts on first run
    /// Creates an "Existing Entries" profile if any non-system entries are found
    private func migrateExistingSystemHosts() async throws {
        let url = systemHostsURL
        let parser = parser
        try validateSystemHostsSize()

        // Read on background thread
        let userEntries = try await Task.detached(priority: .userInitiated) {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = parser.parse(content)
            let allEntries = parser.extractEntries(from: lines)
            return parser.extractUserEntries(from: allEntries)
        }.value

        guard !userEntries.isEmpty else {
            logger.debug(" No user entries found in /etc/hosts, skipping migration")
            return
        }

        logger.debug(" Found \(userEntries.count) user entries in /etc/hosts, creating backup profile...")

        let backupProfile = Profile(
            name: "Existing Entries",
            entries: userEntries,
            isActive: false,
            source: .system,
            colorTag: .gray,
            sortOrder: 0
        )

        try await save(profile: backupProfile)
        profiles.append(backupProfile)
        logger.debug(" Created 'Existing Entries' profile with \(userEntries.count) entries")
    }

    // MARK: - CRUD Operations

    /// Get the next available sort order
    private var nextSortOrder: Int {
        (profiles.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Sanitize and validate a profile name
    private func sanitizedName(_ name: String) throws -> String {
        let cleaned = HostsSanitizer.comment(name)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !cleaned.isEmpty else {
            throw ProfileStoreError.invalidName("Name cannot be empty")
        }
        // Limit length to prevent filesystem issues
        let maxLength = 100
        return String(cleaned.prefix(maxLength))
    }

    /// Create a new profile
    public func create(name: String, from template: ProfileTemplate? = nil) async throws -> Profile {
        let safeName = try sanitizedName(name)
        let profile = Profile(
            name: safeName,
            entries: template?.entries ?? [],
            isActive: false,
            colorTag: template?.colorTag ?? .gray,
            sortOrder: nextSortOrder
        )

        return try await saveCreatedProfile(profile)
    }

    /// Create a profile from a remote source
    public func createRemote(name: String, url: URL, entries: [HostEntry], maxEntries: Int = 500_000) async throws -> Profile {
        let safeName = try sanitizedName(name)
        // Limit entries to prevent crashes with extremely large files
        let limitedEntries = entries.count > maxEntries ? Array(entries.prefix(maxEntries)) : entries

        let profile = Profile(
            name: safeName,
            entries: limitedEntries,
            isActive: false,
            source: .remote(url: url, lastFetched: Date()),
            colorTag: .blue,
            sortOrder: nextSortOrder
        )

        try await saveImportedProfile(profile)
        return profile
    }

    /// Create a profile from merged sources
    public func createMerged(name: String, entries: [HostEntry], sourceCount: Int, maxEntries: Int = 500_000) async throws -> Profile {
        let safeName = try sanitizedName(name)
        // Limit entries to prevent crashes with extremely large files
        let limitedEntries = entries.count > maxEntries ? Array(entries.prefix(maxEntries)) : entries

        let profile = Profile(
            name: safeName,
            entries: limitedEntries,
            isActive: false,
            source: .merged(sourceCount: sourceCount),
            colorTag: .purple,
            sortOrder: nextSortOrder
        )

        try await saveImportedProfile(profile)
        return profile
    }

    private func saveCreatedProfile(_ profile: Profile) async throws -> Profile {
        try await save(profile: profile)
        insertProfile(profile)
        return profile
    }

    private func saveImportedProfile(_ profile: Profile) async throws {
        try createProfilesDirectoryIfNeeded()
        let fileURL = profilesDirectoryURL.appendingPathComponent("\(profile.id.uuidString).json")
        try await writeProfile(profile, to: fileURL)
        insertProfile(profile)
    }

    private func writeProfile(_ profile: Profile, to fileURL: URL) async throws {
        guard !profile.hasPartialEntries else {
            throw ProfileStoreError.partialProfileRequiresHydration
        }
        try await Task.detached(priority: .userInitiated) {
            var toEncode = profile
            toEncode.modifiedAt = Date()
            let data = try JSONEncoder().encode(toEncode)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }.value
    }

    private func insertProfile(_ profile: Profile) {
        profiles.append(profile)
        sortProfiles()
    }

    private func sortProfiles() {
        profiles.sort { lhs, rhs in
            lhs.sortOrder < rhs.sortOrder ||
                (lhs.sortOrder == rhs.sortOrder && lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending)
        }
    }

    /// Save a profile to disk
    public func save(profile: Profile) async throws {
        guard !profile.hasPartialEntries else {
            throw ProfileStoreError.partialProfileRequiresHydration
        }
        var updatedProfile = profile
        updatedProfile.modifiedAt = Date()

        // Encode and write on background thread to avoid blocking UI for large profiles
        let profileToSave = updatedProfile
        let fileURL = profilesDirectoryURL.appendingPathComponent("\(profile.id.uuidString).json")

        try await Task.detached(priority: .userInitiated) {
            let data = try JSONEncoder().encode(profileToSave)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }.value

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

        // Backup before delete for recovery
        backupArchive.backup(profile)

        let fileURL = profilesDirectoryURL.appendingPathComponent("\(profile.id.uuidString).json")
        try fileManager.removeItem(at: fileURL)

        profiles.removeAll { $0.id == profile.id }
        notifyChange()
    }

    /// Batch delete multiple profiles by ID (skips active profiles)
    /// Synchronous to avoid race conditions with UI updates
    public func deleteProfiles(ids: [UUID]) {
        let idsToRemove = Set(ids)

        // Backup profiles before deletion
        for profile in profiles where idsToRemove.contains(profile.id) && !profile.isActive {
            backupArchive.backup(profile)
        }

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
        let sourceProfile = try await fullProfile(for: profile)
        let newProfile = Profile(
            id: UUID(),
            name: generateUniqueName(baseName: sourceProfile.name),
            entries: sourceProfile.entries,
            isActive: false,
            createdAt: Date(),
            modifiedAt: Date(),
            source: sourceProfile.source,
            colorTag: sourceProfile.colorTag,
            sortOrder: nextSortOrder
        )

        return try await saveCreatedProfile(newProfile)
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
        let safeName = try sanitizedName(name)
        // Collect all entries, deduplicating by hostname
        var seenHostnames: Set<String> = []
        var mergedEntries: [HostEntry] = []

        for profile in profilesToMerge {
            let fullProfile = try await fullProfile(for: profile)
            for entry in fullProfile.entries {
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
            name: safeName,
            entries: mergedEntries,
            isActive: false,
            createdAt: Date(),
            modifiedAt: Date(),
            source: .merged(sourceCount: profilesToMerge.count),
            colorTag: .purple,
            sortOrder: nextSortOrder
        )

        return try await saveCreatedProfile(newProfile)
    }

    // MARK: - Reordering

    /// Move profiles from source indices to destination index
    public func moveProfiles(from source: IndexSet, to destination: Int) async throws {
        profiles.move(fromOffsets: source, toOffset: destination)

        // Reassign sort orders based on new positions
        for (index, profile) in profiles.enumerated() {
            if profile.sortOrder != index {
                var updated = try await fullProfile(for: profile)
                updated.sortOrder = index
                try await save(profile: updated)
            }
        }
    }

    // MARK: - Activation

    /// Activate a profile (writes to /etc/hosts via helper)
    /// Returns the hosts content that should be written
    public func prepareActivation(profile: Profile) -> String {
        parser.merge(profile: profile, systemEntries: systemEntries)
    }

    /// Mark a profile as active (after successful write)
    public func markAsActive(profile: Profile) async throws {
        let profile = try await fullProfile(for: profile)

        // Deactivate current active profile
        if let current = activeProfile, current.id != profile.id {
            var deactivated = try await fullProfile(for: current)
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

        var deactivated = try await fullProfile(for: current)
        deactivated.isActive = false
        try await save(profile: deactivated)

        activeProfile = nil
        notifyChange()
    }

    // MARK: - Entry Management

    /// Add an entry to a profile
    public func addEntry(_ entry: HostEntry, to profile: Profile) async throws {
        guard let currentSummary = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }
        var updated = try await fullProfile(for: currentSummary)
        updated.entries.append(entry)
        try await save(profile: updated)
    }

    /// Add multiple entries to a profile (batch operation)
    /// Limits to maxEntries to prevent memory issues with extremely large hosts files
    public func addEntries(_ entries: [HostEntry], to profile: Profile, maxEntries: Int = 500_000) async throws {
        guard let currentSummary = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }
        let current = try await fullProfile(for: currentSummary)

        // Limit entries to prevent crashes with extremely large files
        let limitedEntries = entries.count > maxEntries ? Array(entries.prefix(maxEntries)) : entries

        var updated = current
        updated.entries.append(contentsOf: limitedEntries)
        try await save(profile: updated)
    }

    /// Remove an entry from a profile
    public func removeEntry(_ entry: HostEntry, from profile: Profile) async throws {
        var updated = try await fullProfile(for: profile)
        updated.entries.removeAll { $0.id == entry.id }
        try await save(profile: updated)
    }

    /// Update an entry in a profile
    public func updateEntry(_ entry: HostEntry, in profile: Profile) async throws {
        var updated = try await fullProfile(for: profile)
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
        guard let currentSummary = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }

        var updated = try await fullProfile(for: currentSummary)
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
        guard let currentSummary = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }

        var updated = try await fullProfile(for: currentSummary)
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
        parser.merge(profile: profile, systemEntries: systemEntries)
    }

    private func validateSystemHostsSize() throws {
        let attributes = try fileManager.attributesOfItem(atPath: systemHostsURL.path)
        let size = attributes[.size] as? Int64 ?? 0
        guard size <= maxSystemHostsBytes else {
            throw ProfileStoreError.loadFailed("/etc/hosts is too large to import automatically")
        }
    }
}

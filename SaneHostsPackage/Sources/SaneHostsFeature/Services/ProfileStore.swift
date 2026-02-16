import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "ProfileStore")

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
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return appSupport.appendingPathComponent("SaneHosts/Profiles", isDirectory: true)
    }

    /// URL for profile backups (crash resilience)
    private var backupsDirectoryURL: URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return appSupport.appendingPathComponent("SaneHosts/Backups", isDirectory: true)
    }

    /// URL for the system hosts file
    private let systemHostsURL = URL(fileURLWithPath: "/etc/hosts")

    /// Maximum number of backups to keep per profile
    private let maxBackupsPerProfile = 3

    // MARK: - Initialization

    public init() {}

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

            // Create Essentials profile if none exist (migration may have created one)
            if profiles.isEmpty {
                logger.debug(" No profiles found, creating Essentials preset...")
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
        if !fileManager.fileExists(atPath: profilesDirectoryURL.path) {
            try fileManager.createDirectory(at: profilesDirectoryURL, withIntermediateDirectories: true)
        }
        // Also create backups directory
        if !fileManager.fileExists(atPath: backupsDirectoryURL.path) {
            try fileManager.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Preset Profiles

    /// Create the Essentials preset profile on first launch
    private func createEssentialsProfile() async {
        logger.debug("Creating Essentials preset profile...")

        do {
            // Load entries from PresetManager (will fetch from network if needed)
            let entries = try await PresetManager.shared.loadEntries(for: .essentials)
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

    /// Create a backup of a profile before destructive operations
    private func backupProfile(_ profile: Profile) {
        let sourceURL = profilesDirectoryURL.appendingPathComponent("\(profile.id.uuidString).json")
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupName = "\(profile.id.uuidString)_\(timestamp).json"
        let backupURL = backupsDirectoryURL.appendingPathComponent(backupName)

        do {
            try fileManager.copyItem(at: sourceURL, to: backupURL)
            cleanupOldBackups(for: profile.id)
            logger.debug(" Backup created: \(backupName)")
        } catch {
            logger.debug(" Backup failed: \(error.localizedDescription)")
        }
    }

    /// Remove old backups keeping only the most recent ones
    private func cleanupOldBackups(for profileId: UUID) {
        do {
            let files = try fileManager.contentsOfDirectory(at: backupsDirectoryURL, includingPropertiesForKeys: [.creationDateKey])
            let profileBackups = files
                .filter { $0.lastPathComponent.hasPrefix(profileId.uuidString) }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return date1 > date2
                }

            // Delete backups beyond the limit
            for backup in profileBackups.dropFirst(maxBackupsPerProfile) {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            logger.debug(" Cleanup failed: \(error.localizedDescription)")
        }
    }

    /// Attempt to recover a corrupted profile from backup
    private func recoverProfile(id: UUID) -> Profile? {
        do {
            let files = try fileManager.contentsOfDirectory(at: backupsDirectoryURL, includingPropertiesForKeys: [.creationDateKey])
            let backups = files
                .filter { $0.lastPathComponent.hasPrefix(id.uuidString) }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return date1 > date2
                }

            for backup in backups {
                do {
                    let data = try Data(contentsOf: backup)
                    let profile = try JSONDecoder().decode(Profile.self, from: data)
                    logger.debug(" Recovered profile from backup: \(backup.lastPathComponent)")
                    return profile
                } catch {
                    continue // Try next backup
                }
            }
        } catch {
            logger.debug(" Recovery scan failed: \(error.localizedDescription)")
        }
        return nil
    }

    private func loadSystemHosts() async throws {
        let url = systemHostsURL
        let parser = parser

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

    private func loadProfiles() async throws {
        let profilesDir = profilesDirectoryURL

        // Phase 1: Read and decode valid profiles in background
        let result = try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }

            var validProfiles: [Profile] = []
            var corruptedFiles: [URL] = []

            for file in jsonFiles {
                do {
                    let data = try Data(contentsOf: file)

                    // Validate JSON structure before decoding
                    guard !data.isEmpty else {
                        logger.debug(" Empty file detected: \(file.lastPathComponent)")
                        corruptedFiles.append(file)
                        continue
                    }

                    let profile = try JSONDecoder().decode(Profile.self, from: data)

                    // Basic validation: ensure profile has required data
                    guard !profile.name.isEmpty else {
                        logger.debug(" Invalid profile (empty name): \(file.lastPathComponent)")
                        corruptedFiles.append(file)
                        continue
                    }

                    validProfiles.append(profile)
                } catch {
                    logger.debug(" Failed to load \(file.lastPathComponent): \(error.localizedDescription)")
                    corruptedFiles.append(file)
                }
            }
            return LoadResult(validProfiles: validProfiles, corruptedFiles: corruptedFiles)
        }.value

        var loadedProfiles = result.validProfiles
        let corruptedFiles = result.corruptedFiles

        // Phase 2: Handle corrupted files (Main Actor)
        for file in corruptedFiles {
            // Attempt recovery from backup
            let filename = file.deletingPathExtension().lastPathComponent
            if let profileId = UUID(uuidString: filename),
               let recovered = recoverProfile(id: profileId) {
                loadedProfiles.append(recovered)
                // Restore the recovered profile to the main directory
                try? await save(profile: recovered)
            } else {
                // Move corrupted files to a quarantine location instead of deleting
                let quarantineName = "CORRUPTED_\(file.lastPathComponent)"
                let quarantineURL = backupsDirectoryURL.appendingPathComponent(quarantineName)
                try? fileManager.moveItem(at: file, to: quarantineURL)
                logger.debug(" Quarantined corrupted file: \(quarantineName)")
            }
        }

        profiles = loadedProfiles.sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) }
        activeProfile = profiles.first { $0.isActive }
    }

    /// Migrate existing user entries from /etc/hosts on first run
    /// Creates an "Existing Entries" profile if any non-system entries are found
    private func migrateExistingSystemHosts() async throws {
        let url = systemHostsURL
        let parser = parser

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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProfileStoreError.invalidName("Name cannot be empty")
        }
        // Limit length to prevent filesystem issues
        let maxLength = 100
        return String(trimmed.prefix(maxLength))
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

        try await save(profile: profile)
        profiles.append(profile)
        profiles.sort { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending) }

        return profile
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

        // Ensure profiles directory exists before writing
        try createProfilesDirectoryIfNeeded()

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

        // Ensure profiles directory exists before writing
        try createProfilesDirectoryIfNeeded()

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

        // Encode and write on background thread to avoid blocking UI for large profiles
        let profileToSave = updatedProfile
        let fileURL = profilesDirectoryURL.appendingPathComponent("\(profile.id.uuidString).json")

        try await Task.detached(priority: .userInitiated) {
            let data = try JSONEncoder().encode(profileToSave)
            try data.write(to: fileURL, options: .atomic)
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
        backupProfile(profile)

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
            backupProfile(profile)
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
        let safeName = try sanitizedName(name)
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
            name: safeName,
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
        parser.merge(profile: profile, systemEntries: systemEntries)
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
    public func addEntries(_ entries: [HostEntry], to profile: Profile, maxEntries: Int = 500_000) async throws {
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
        parser.merge(profile: profile, systemEntries: systemEntries)
    }
}

// MARK: - Private Helpers

private struct LoadResult: Sendable {
    var validProfiles: [Profile]
    var corruptedFiles: [URL]
}

// MARK: - Errors

public enum ProfileStoreError: LocalizedError {
    case loadFailed(String)
    case saveFailed(String)
    case cannotDeleteActive
    case profileNotFound
    case invalidName(String)

    public var errorDescription: String? {
        switch self {
        case let .loadFailed(reason): "Failed to load profiles: \(reason)"
        case let .saveFailed(reason): "Failed to save profile: \(reason)"
        case .cannotDeleteActive: "Cannot delete the active profile. Deactivate it first."
        case .profileNotFound: "Profile not found"
        case let .invalidName(reason): "Invalid profile name: \(reason)"
        }
    }
}

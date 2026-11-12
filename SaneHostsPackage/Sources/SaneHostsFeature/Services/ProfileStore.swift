import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "ProfileStore")

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

    /// First-run used to persist a zero-entry Essentials stub when bundled
    /// lists were missing. That stub must be refilled, not treated as done.
    public static func emptyEssentialsProfile(in profiles: [Profile]) -> Profile? {
        profiles.first { profile in
            profile.name.caseInsensitiveCompare(ProfilePreset.essentials.displayName) == .orderedSame
                && profile.entryCount == 0
        }
    }
}

@MainActor
@Observable
public final class ProfileStore {
    // MARK: - Shared Instance

    public static let shared: ProfileStore = {
        if let root = fixtureStorageRoot() {
            return ProfileStore(storageRootURL: root, systemHostsURL: URL(fileURLWithPath: "/etc/hosts"))
        }
        return ProfileStore()
    }()

    /// Customer-UI fixture must not read the real Application Support tree.
    /// macOS 26 ignores HOME / CFFIXED_USER_HOME for FileManager user-domain URLs.
    nonisolated static func fixtureStorageRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard environment["SANEHOSTS_CUSTOMER_UI_FIXTURE"] == "1" else { return nil }
        if let path = environment["SANEHOSTS_FIXTURE_STORAGE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("sanehosts-customer-ui", isDirectory: true)
    }

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
    private var loadTask: Task<Void, Never>?
    private let profilesDirectoryOverrideURL: URL?
    private let backupsDirectoryOverrideURL: URL?

    private var profilesDirectoryURL: URL {
        if let profilesDirectoryOverrideURL {
            return profilesDirectoryOverrideURL
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return appSupport.appendingPathComponent("SaneHosts/Profiles", isDirectory: true)
    }

    private var backupsDirectoryURL: URL {
        if let backupsDirectoryOverrideURL {
            return backupsDirectoryOverrideURL
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return appSupport.appendingPathComponent("SaneHosts/Backups", isDirectory: true)
    }

    private let systemHostsURL: URL

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

    public func load() async {
        if let loadTask {
            logger.debug("Joining in-flight profile load")
            await loadTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performLoad()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        logger.debug(" load() started")
        isLoading = true
        error = nil

        do {
            logger.debug(" Creating profiles directory...")
            try createProfilesDirectoryIfNeeded()

            logger.debug("Loading system hosts...")
            try await loadSystemHosts()
            let sysCount = systemEntries.count
            logger.debug("System hosts loaded: \(sysCount) entries")

            logger.debug("Loading profiles...")
            try await loadProfiles()
            let profCount = profiles.count
            logger.debug("Loaded \(profCount) profiles")

            if profiles.isEmpty {
                logger.debug(" First run - checking for existing user hosts entries...")
                try await migrateExistingSystemHosts()
            }

            // Basic must always have the free Essentials profile, even when
            // first-run migration created an "Existing Entries" profile.
            if ProfileStoreEssentialsPolicy.needsEssentialsProfile(profiles: profiles) {
                logger.debug(" Essentials profile missing, creating Essentials preset...")
                await createEssentialsProfile()
            } else if let emptyEssentials = ProfileStoreEssentialsPolicy.emptyEssentialsProfile(in: profiles) {
                logger.debug(" Essentials profile is empty, refilling preset lists...")
                await refillEssentialsProfile(emptyEssentials)
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

    private func createEssentialsProfile() async {
        logger.debug("Creating Essentials preset profile...")

        do {
            let entries = try await loadEssentialsEntries()
            guard !entries.isEmpty else {
                logger.debug("Skipping empty Essentials create; lists were not available")
                return
            }

            let essentialsProfile = ProfilePreset.essentials.createProfile(with: entries)
            profiles.append(essentialsProfile)
            try await save(profile: essentialsProfile)
            logger.debug("Essentials profile created with \(entries.count) entries")
        } catch {
            logger.debug("Failed to load Essentials preset: \(error.localizedDescription)")
        }
    }

    private func refillEssentialsProfile(_ profile: Profile) async {
        do {
            let entries = try await loadEssentialsEntries()
            guard !entries.isEmpty else {
                logger.debug("Essentials refill found no lists yet")
                return
            }
            var updated = profile
            updated.entries = entries
            updated.colorTag = ProfilePreset.essentials.colorTag
            try await save(profile: updated)
            logger.debug("Refilled Essentials with \(entries.count) entries")
        } catch {
            logger.debug("Failed to refill Essentials: \(error.localizedDescription)")
        }
    }

    private func loadEssentialsEntries() async throws -> [HostEntry] {
        let local = try await PresetManager.shared.loadEntries(for: .essentials, allowNetworkFetch: false)
        if !local.isEmpty {
            return local
        }
        return try await PresetManager.shared.loadEntries(for: .essentials, allowNetworkFetch: true)
    }

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

            let headerContent: String = if let markerRange = content.range(of: "# ---- Profile:") {
                String(content[content.startIndex ..< markerRange.lowerBound])
            } else {
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
        let fileURL = profileFileURL(for: profile.id)
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

    private var nextSortOrder: Int {
        (profiles.map(\.sortOrder).max() ?? -1) + 1
    }

    private func sanitizedName(_ name: String) throws -> String {
        let cleaned = HostsSanitizer.comment(name)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !cleaned.isEmpty else {
            throw ProfileStoreError.invalidName("Name cannot be empty")
        }
        let maxLength = 100
        return String(cleaned.prefix(maxLength))
    }

    public func create(name: String, from template: ProfileTemplate? = nil, colorTag: ProfileColor? = nil) async throws -> Profile {
        let safeName = try sanitizedName(name)
        let profile = Profile(
            name: safeName,
            entries: template?.entries ?? [],
            isActive: false,
            colorTag: colorTag ?? template?.colorTag ?? .gray,
            sortOrder: nextSortOrder
        )

        return try await saveCreatedProfile(profile)
    }

    public func createRemote(name: String, url: URL, entries: [HostEntry]) async throws -> Profile {
        try await createImported(
            name: name,
            entries: entries,
            source: .remote(url: url, lastFetched: Date()),
            colorTag: .blue,
            sourceURLs: nil
        )
    }

    public func createMerged(name: String, entries: [HostEntry], sourceCount: Int, sourceURLs: [URL]? = nil) async throws -> Profile {
        try await createImported(
            name: name,
            entries: entries,
            source: .merged(sourceCount: sourceCount),
            colorTag: .purple,
            sourceURLs: sourceURLs
        )
    }

    private func createImported(
        name: String,
        entries: [HostEntry],
        source: ProfileSource,
        colorTag: ProfileColor,
        sourceURLs: [URL]?
    ) async throws -> Profile {
        let profile = try Profile(
            name: sanitizedName(name),
            entries: Array(entries.prefix(BlocklistMerge.maxEntries)),
            isActive: false,
            source: source,
            colorTag: colorTag,
            sortOrder: nextSortOrder,
            sourceURLs: sourceURLs,
            listsUpdatedAt: Date()
        )
        return try await saveCreatedProfile(profile)
    }

    private func saveCreatedProfile(_ profile: Profile) async throws -> Profile {
        try createProfilesDirectoryIfNeeded()
        try await save(profile: profile)
        insertProfile(profile)
        return profile
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

    private func profileFileURL(for id: UUID) -> URL {
        profilesDirectoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    /// Writes off the main thread; large profiles take a while to encode.
    public func save(profile: Profile) async throws {
        guard !profile.hasPartialEntries else {
            throw ProfileStoreError.partialProfileRequiresHydration
        }
        var updatedProfile = profile
        updatedProfile.modifiedAt = Date()

        let profileToSave = updatedProfile
        let fileURL = profileFileURL(for: profile.id)

        try await Task.detached(priority: .userInitiated) {
            let data = try JSONEncoder().encode(profileToSave)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }.value

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = updatedProfile
        }
        if activeProfile?.id == profile.id {
            activeProfile = updatedProfile
        }
        notifyChange()
    }

    public func delete(profile: Profile) async throws {
        guard !profile.isActive else {
            throw ProfileStoreError.cannotDeleteActive
        }

        backupArchive.backup(profile)
        try fileManager.removeItem(at: profileFileURL(for: profile.id))

        profiles.removeAll { $0.id == profile.id }
        notifyChange()
    }

    /// Skips active profiles. Synchronous to avoid races with UI updates.
    public func deleteProfiles(ids: [UUID]) {
        let deletable = profiles.filter { ids.contains($0.id) && !$0.isActive }
        let idsToRemove = Set(deletable.map(\.id))

        for profile in deletable {
            backupArchive.backup(profile)
            try? fileManager.removeItem(at: profileFileURL(for: profile.id))
        }

        profiles.removeAll { idsToRemove.contains($0.id) }
        notifyChange()
    }

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
            sortOrder: nextSortOrder,
            sourceURLs: sourceProfile.sourceURLs,
            listsUpdatedAt: sourceProfile.listsUpdatedAt
        )

        return try await saveCreatedProfile(newProfile)
    }

    /// "Default" becomes "Default 1", "Default 2", and so on.
    private func generateUniqueName(baseName: String) -> String {
        let cleanBase = baseName
            .replacingOccurrences(of: #" Copy( Copy)*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression)

        let existingNames = Set(profiles.map(\.name))
        var counter = 1
        var candidateName = "\(cleanBase) \(counter)"
        while existingNames.contains(candidateName) {
            counter += 1
            candidateName = "\(cleanBase) \(counter)"
        }
        return candidateName
    }

    /// Keeps the first entry for each set of hostnames.
    public func merge(profiles profilesToMerge: [Profile], name: String) async throws -> Profile {
        let safeName = try sanitizedName(name)
        var allEntries: [HostEntry] = []
        for profile in profilesToMerge {
            let fullProfile = try await fullProfile(for: profile)
            allEntries.append(contentsOf: fullProfile.entries)
        }
        let mergedEntries = BlocklistMerge.deduplicated(allEntries, limit: .max)

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

    public func moveProfiles(from source: IndexSet, to destination: Int) async throws {
        profiles.move(fromOffsets: source, toOffset: destination)
        for (index, profile) in profiles.enumerated() {
            if profile.sortOrder != index {
                var updated = try await fullProfile(for: profile)
                updated.sortOrder = index
                try await save(profile: updated)
            }
        }
    }

    // MARK: - Activation

    /// Call only after the hosts file was written.
    public func markAsActive(profile: Profile) async throws {
        let profile = try await fullProfile(for: profile)

        if let current = activeProfile, current.id != profile.id {
            var deactivated = try await fullProfile(for: current)
            deactivated.isActive = false
            try await save(profile: deactivated)
        }

        var activated = profile
        activated.isActive = true
        try await save(profile: activated)

        activeProfile = activated
        notifyChange()
    }

    public func deactivate() async throws {
        guard let current = activeProfile else { return }

        var deactivated = try await fullProfile(for: current)
        deactivated.isActive = false
        try await save(profile: deactivated)

        activeProfile = nil
        notifyChange()
    }

    // MARK: - Entry Management

    /// Edits to the active profile are applied by the next list update, so
    /// the protection lock covers them too.
    private func unlockIfActive(_ profile: Profile) async throws {
        let isActive = profiles.first { $0.id == profile.id }?.isActive ?? profile.isActive
        guard isActive else { return }
        try await ProtectionController.unlock("change the active profile")
    }

    public func addEntry(_ entry: HostEntry, to profile: Profile) async throws {
        try await unlockIfActive(profile)
        guard let currentSummary = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }
        var updated = try await fullProfile(for: currentSummary)
        updated.entries.append(entry)
        try await save(profile: updated)
    }

    public func addEntries(_ entries: [HostEntry], to profile: Profile, maxEntries: Int = BlocklistMerge.maxEntries) async throws {
        try await unlockIfActive(profile)
        guard let currentSummary = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }
        var updated = try await fullProfile(for: currentSummary)
        updated.entries.append(contentsOf: entries.prefix(maxEntries))
        try await save(profile: updated)
    }

    public func removeEntry(_ entry: HostEntry, from profile: Profile) async throws {
        try await unlockIfActive(profile)
        var updated = try await fullProfile(for: profile)
        updated.entries.removeAll { $0.id == entry.id }
        try await save(profile: updated)
    }

    public func updateEntry(_ entry: HostEntry, in profile: Profile) async throws {
        try await unlockIfActive(profile)
        var updated = try await fullProfile(for: profile)
        if let index = updated.entries.firstIndex(where: { $0.id == entry.id }) {
            updated.entries[index] = entry
            try await save(profile: updated)
        }
    }

    public func toggleEntry(_ entry: HostEntry, in profile: Profile) async throws {
        var updatedEntry = entry
        updatedEntry.isEnabled.toggle()
        try await updateEntry(updatedEntry, in: profile)
    }

    /// One disk write for the whole batch.
    public func bulkUpdateEntries(ids: Set<UUID>, in profile: Profile, update: (inout HostEntry) -> Void) async throws {
        try await unlockIfActive(profile)
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

    /// One disk write for the whole batch.
    public func bulkRemoveEntries(ids: Set<UUID>, from profile: Profile) async throws {
        try await unlockIfActive(profile)
        guard let currentSummary = profiles.first(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.profileNotFound
        }

        var updated = try await fullProfile(for: currentSummary)
        updated.entries.removeAll { ids.contains($0.id) }
        try await save(profile: updated)
    }

    // MARK: - Import/Export

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

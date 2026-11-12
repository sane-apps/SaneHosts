import Foundation

/// The one path that turns protection on, off, or re-applies it. The main
/// window, the menu bar, the allowlist and list updates all go through here,
/// so the allowlist and the optional protection lock apply to every write.
@MainActor
public enum ProtectionController {
    /// - Returns: A warning when the hosts file was written but the DNS cache refresh failed.
    @discardableResult
    public static func activate(
        _ profile: Profile,
        interactive: Bool = true,
        requireUnlock: Bool = true,
        store: ProfileStore = .shared,
        hosts: HostsService = .shared,
        allowlist: AllowlistStore = .shared
    ) async throws -> String? {
        if requireUnlock, let reason = unlockReason(activating: profile, active: store.activeProfile) {
            try await unlock(reason)
        }
        let fullProfile = try await store.fullProfile(for: profile)
        let warning = try await hosts.activateProfile(
            fullProfile,
            systemEntries: store.systemEntries,
            allowlist: allowlist.allowlist,
            interactive: interactive
        )
        try await markActiveAfterWrite(fullProfile, store: store)
        return warning
    }

    @discardableResult
    public static func deactivate(
        requireUnlock: Bool = true,
        store: ProfileStore = .shared,
        hosts: HostsService = .shared
    ) async throws -> String? {
        if requireUnlock {
            try await unlock("turn off protection")
        }
        let warning = try await hosts.deactivateProfile()
        do {
            try await store.deactivate()
        } catch {
            try await store.deactivate()
        }
        return warning
    }

    /// Writes the active profile again, for example after the allowlist or
    /// its lists changed. Does nothing when protection is off.
    @discardableResult
    public static func reapplyActiveProfile(
        interactive: Bool = true,
        requireUnlock: Bool = true,
        store: ProfileStore = .shared
    ) async throws -> String? {
        guard let active = store.activeProfile else { return nil }
        let current = store.profiles.first { $0.id == active.id } ?? active
        return try await activate(current, interactive: interactive, requireUnlock: requireUnlock, store: store)
    }

    /// Turning protection on from off only adds blocking, so it never asks.
    /// Switching away from the active profile can remove blocking, so it does.
    nonisolated static func unlockReason(activating profile: Profile, active: Profile?) -> String? {
        guard let active, active.id != profile.id else { return nil }
        return "switch protection to \(profile.name)"
    }

    /// Cancelling the Touch ID or password prompt is a quiet cancel, like
    /// cancelling any other macOS authentication.
    public static func unlock(_ reason: String) async throws {
        guard await ProtectionLock.authorize(reason) else {
            throw HostsServiceError.userCancelled
        }
    }

    /// The hosts file is already written at this point, so a failed local
    /// save is retried once to keep the UI in step with what is on disk.
    private static func markActiveAfterWrite(_ profile: Profile, store: ProfileStore) async throws {
        do {
            try await store.markAsActive(profile: profile)
        } catch {
            try await store.markAsActive(profile: profile)
        }
    }
}

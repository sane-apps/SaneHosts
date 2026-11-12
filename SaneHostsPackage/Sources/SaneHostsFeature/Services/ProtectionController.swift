import Foundation

/// The one path that turns protection on, off, or re-applies it. The main
/// window, the menu bar, the allowlist and list updates all go through here,
/// so the allowlist is applied to every write.
@MainActor
public enum ProtectionController {
    /// - Returns: A warning when the hosts file was written but the DNS cache refresh failed.
    @discardableResult
    public static func activate(
        _ profile: Profile,
        interactive: Bool = true,
        store: ProfileStore = .shared,
        hosts: HostsService = .shared,
        allowlist: AllowlistStore = .shared
    ) async throws -> String? {
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
        store: ProfileStore = .shared,
        hosts: HostsService = .shared
    ) async throws -> String? {
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
        store: ProfileStore = .shared
    ) async throws -> String? {
        guard let active = store.activeProfile else { return nil }
        let current = store.profiles.first { $0.id == active.id } ?? active
        return try await activate(current, interactive: interactive, store: store)
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

import Foundation

/// Optional lock (Settings > General > Protection Lock). When it is on,
/// turning protection off, switching to another profile and changing Allowed Sites ask
/// for Touch ID or the Mac password first, and so do edits to the active
/// profile. List updates are not locked: they only refresh the lists the
/// person already chose. After one unlock, changes in the next two minutes
/// do not ask again, like sudo.
@MainActor
public enum ProtectionLock {
    public nonisolated static let enabledKey = "protectionLockEnabled"
    static let graceSeconds: TimeInterval = 120
    static var lastUnlock: Date?

    /// Tests swap these to avoid real prompts and real preferences.
    static var defaults: UserDefaults = .standard
    static var authenticate: (String) async -> Bool = { reason in
        await AuthenticationService().authenticate(reason: reason)
    }
    static var now: () -> Date = Date.init

    public static var isEnabled: Bool {
        defaults.bool(forKey: enabledKey)
    }

    /// True when the lock is off or the person authenticated. `reason` finishes
    /// the macOS sentence "SaneHosts is trying to ...".
    public static func authorize(_ reason: String) async -> Bool {
        guard isEnabled else { return true }
        if let lastUnlock, now().timeIntervalSince(lastUnlock) < graceSeconds {
            return true
        }
        guard await authenticate(reason) else { return false }
        lastUnlock = now()
        return true
    }

    /// Turning the lock off always needs authentication, so the lock cannot be
    /// removed by whoever it is meant to stop.
    public static func setEnabled(_ enabled: Bool) async -> Bool {
        if !enabled, isEnabled {
            guard await authenticate("turn off the protection lock") else { return false }
        }
        lastUnlock = nil
        defaults.set(enabled, forKey: enabledKey)
        return true
    }
}

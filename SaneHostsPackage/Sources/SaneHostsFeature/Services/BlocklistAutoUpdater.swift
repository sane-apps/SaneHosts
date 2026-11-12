import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "BlocklistAutoUpdater")

/// Keeps the active profile's lists current while SaneHosts runs. It only
/// writes when the helper can do so without a password prompt, so it never
/// interrupts the user.
@MainActor
public final class BlocklistAutoUpdater {
    public static let shared = BlocklistAutoUpdater()

    public nonisolated static let enabledKey = "autoUpdateLists"
    public nonisolated static let lastCheckKey = "lastAutoListCheck"
    nonisolated static let interval: TimeInterval = 7 * 24 * 60 * 60
    private static let pollInterval: TimeInterval = 6 * 60 * 60
    private static let launchDelay: Duration = .seconds(90)

    private let defaults: UserDefaults
    private var timer: Timer?
    private var isRunning = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public nonisolated static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    public nonisolated static func lastCheck(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastCheckKey) as? Date
    }

    nonisolated static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    public func start() {
        guard timer == nil, ProfileStore.fixtureStorageRoot() == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor in
                await BlocklistAutoUpdater.shared.runIfDue()
            }
        }
        Task {
            try? await Task.sleep(for: Self.launchDelay)
            await runIfDue()
        }
    }

    func runIfDue(now: Date = Date(), store: ProfileStore = .shared) async {
        guard Self.isEnabled(defaults), !isRunning,
              Self.isDue(lastCheck: Self.lastCheck(defaults), now: now) else { return }
        isRunning = true
        defer { isRunning = false }

        if store.profiles.isEmpty {
            await store.load()
        }
        guard let active = store.activeProfile, BlocklistUpdater.canUpdate(active) else {
            defaults.set(now, forKey: Self.lastCheckKey)
            return
        }
        guard await HostsService.shared.canWriteWithoutPrompt() else {
            logger.info("Skipping list update: helper not available for a silent write")
            return
        }

        do {
            let result = try await BlocklistUpdater.update(active, interactive: false, store: store)
            defaults.set(now, forKey: Self.lastCheckKey)
            logger.info("Weekly list update finished: \(result.previousCount) -> \(result.newCount) entries")
        } catch {
            logger.error("Weekly list update failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

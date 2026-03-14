import Foundation
import SaneHostsFeature
import SaneUI

extension SaneDiagnosticsService {
    static let shared = SaneDiagnosticsService(
        appName: "SaneHosts",
        subsystem: "com.mrsane.SaneHosts",
        githubRepo: "SaneHosts",
        settingsCollector: { await collectSaneHostsSettings() }
    )
}

@MainActor
private func collectSaneHostsSettings() async -> String {
    let defaults = UserDefaults.standard
    let store = ProfileStore.shared
    let hostsService = HostsService.shared
    let helperRunning = await HostsHelperConnection().isHelperRunning()

    return """
    profileCount: \(store.profiles.count)
    activeProfile: \(store.activeProfile?.name ?? "none")
    totalEntryCount: \(store.profiles.reduce(0) { $0 + $1.entries.count })
    helperRunning: \(helperRunning)
    isWritingHostsFile: \(hostsService.isWriting)
    lastWriteError: \(hostsService.lastError?.localizedDescription ?? "none")
    storeIsLoading: \(store.isLoading)
    storeError: \(store.error?.localizedDescription ?? "none")

    settings:
      hideDockIcon: \(defaults.bool(forKey: "hideDockIcon"))
      launchAtLogin: \(SaneLoginItemPolicy.toggleValue())
      hasSeenWelcome: \(defaults.bool(forKey: "hasSeenWelcome"))
      hasSeenWelcomeGate: \(defaults.bool(forKey: "hasSeenWelcomeGate"))
    """
}

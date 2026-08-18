import Foundation
import SaneUI

/// When the 14-day trial ends, protection must actually stop.
/// Leaving an active profile in /etc/hosts would be free forever.
public enum TrialExpiryProtection {
    @MainActor
    public static func deactivateIfNeeded(
        licenseService: LicenseService,
        store: ProfileStore,
        hostsService: HostsService = .shared,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async {
        guard environment["SANEHOSTS_CUSTOMER_UI_FIXTURE"] != "1" else { return }
        guard licenseService.hasExpiredProTrial else { return }
        let hasActive = store.activeProfile != nil || store.profiles.contains(where: \.isActive)
        guard hasActive else { return }

        do {
            _ = try await hostsService.deactivateProfile()
            try await store.deactivate()
        } catch {
            // Next launch retries while a profile is still marked active.
        }
    }
}

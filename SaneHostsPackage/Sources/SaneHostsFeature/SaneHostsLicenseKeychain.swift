import Foundation
import SaneUI

/// Keychain identity for the SaneHosts license, shared across every
/// `LicenseService` construction site in the app.
///
/// `accessGroup` opts the license/trial credentials into the modern
/// data-protection keychain keyed to the Team ID, instead of the legacy login
/// keychain whose per-item ACL is bound to a specific build signature. That
/// legacy binding is what produces the "wants to use your confidential
/// information" prompt storm after an update changes the signature. The value
/// must exactly match the `keychain-access-groups` entitlement, otherwise
/// keychain writes fail with `errSecMissingEntitlement`.
///
/// `service` is pinned to the bundle identifier the previous (legacy) builds
/// used so the one-time migration in `KeychainService` finds and moves the
/// existing items.
public enum SaneHostsLicenseKeychain {
    public static let service = "com.mrsane.SaneHosts"
    public static let accessGroup = "M78L6FXD48.com.mrsane.SaneHosts"

    /// Builds the data-protection-keychain-backed service used for the license.
    public static func makeService() -> KeychainService {
        KeychainService(service: service, accessGroup: accessGroup)
    }
}

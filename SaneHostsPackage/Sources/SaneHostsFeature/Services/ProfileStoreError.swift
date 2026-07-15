import Foundation

/// Errors surfaced by `ProfileStore` and its persistence collaborators.
public enum ProfileStoreError: LocalizedError {
    case loadFailed(String)
    case saveFailed(String)
    case cannotDeleteActive
    case profileNotFound
    case invalidName(String)
    case invalidProfileIdentity(String)
    case partialProfileRequiresHydration

    public var errorDescription: String? {
        switch self {
        case let .loadFailed(reason): "Failed to load profiles: \(reason)"
        case let .saveFailed(reason): "Failed to save profile: \(reason)"
        case .cannotDeleteActive: "Cannot delete the active profile. Deactivate it first."
        case .profileNotFound: "Profile not found"
        case let .invalidName(reason): "Invalid profile name: \(reason)"
        case let .invalidProfileIdentity(reason): "Invalid profile identity: \(reason)"
        case .partialProfileRequiresHydration: "The complete profile must be loaded before it can be saved."
        }
    }
}

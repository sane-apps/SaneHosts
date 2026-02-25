import SaneUI

/// Pro features gated behind a license in SaneHosts.
public enum ProFeature: String, ProFeatureDescribing, CaseIterable, Sendable {
    case multipleProfiles = "Multiple Profiles"
    case downloadablePresets = "Downloadable Presets"
    case profileMerge = "Merge Profiles"
    case bulkOperations = "Bulk Operations"
    case importProfiles = "Import from File / URL"
    case duplicateProfile = "Duplicate Profile"

    public var id: String { rawValue }

    public var featureName: String { rawValue }

    public var featureDescription: String {
        switch self {
        case .multipleProfiles:
            "Create unlimited host profiles for different configurations"
        case .downloadablePresets:
            "One-click install of curated ad blocker, privacy, and security presets"
        case .profileMerge:
            "Combine multiple profiles into a single comprehensive profile"
        case .bulkOperations:
            "Enable or disable multiple host entries at once"
        case .importProfiles:
            "Import hosts from files, URLs, or blocklist services"
        case .duplicateProfile:
            "Clone an existing profile as a starting point"
        }
    }

    public var featureIcon: String {
        switch self {
        case .multipleProfiles: "doc.on.doc"
        case .downloadablePresets: "arrow.down.circle"
        case .profileMerge: "arrow.triangle.merge"
        case .bulkOperations: "checklist"
        case .importProfiles: "square.and.arrow.down"
        case .duplicateProfile: "plus.square.on.square"
        }
    }
}

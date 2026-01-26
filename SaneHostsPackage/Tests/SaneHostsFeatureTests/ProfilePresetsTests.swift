import Testing
import Foundation
@testable import SaneHostsFeature

// MARK: - ProfilePreset Tests

@Suite("ProfilePreset Tests")
struct ProfilePresetTests {

    // MARK: - Properties

    @Test("All protection levels have required properties")
    func allProtectionLevelsHaveProperties() {
        for preset in ProfilePreset.allCases {
            #expect(!preset.displayName.isEmpty)
            #expect(!preset.description.isEmpty)
            #expect(!preset.icon.isEmpty)
            #expect(!preset.tagline.isEmpty)
            #expect(!preset.estimatedEntries.isEmpty)
            #expect(!preset.blocklistSourceIds.isEmpty)

            // colorTag is an enum value — verify it's a valid ProfileColor
            let validColors = ProfileColor.allCases
            #expect(validColors.contains(preset.colorTag))
        }
    }

    // MARK: - Cumulative Hierarchy

    @Test("Blocklist source IDs are cumulative across levels")
    func blocklistSourceIDsAreCumulative() {
        let essentialsIds = Set(ProfilePreset.essentials.blocklistSourceIds)
        let familySafeIds = Set(ProfilePreset.familySafe.blocklistSourceIds)
        let focusModeIds = Set(ProfilePreset.focusMode.blocklistSourceIds)
        let privacyShieldIds = Set(ProfilePreset.privacyShield.blocklistSourceIds)
        let kitchenSinkIds = Set(ProfilePreset.kitchenSink.blocklistSourceIds)

        // Each level includes all IDs from the previous level
        #expect(essentialsIds.isSubset(of: familySafeIds))
        #expect(familySafeIds.isSubset(of: focusModeIds))
        #expect(focusModeIds.isSubset(of: privacyShieldIds))
        #expect(privacyShieldIds.isSubset(of: kitchenSinkIds))
    }

    // MARK: - Catalog Resolution

    @Test("All blocklist source IDs resolve from catalog")
    func blocklistSourceIDsResolveFromCatalog() {
        let catalogIds = Set(BlocklistCatalog.all.map(\.id))

        for preset in ProfilePreset.allCases {
            for sourceId in preset.blocklistSourceIds {
                if !catalogIds.contains(sourceId) {
                    Issue.record("Source ID '\(sourceId)' in preset \(preset.displayName) not found in BlocklistCatalog.all")
                }
            }
        }
    }

    @Test("blocklistSources count matches blocklistSourceIds count")
    func blocklistSourcesMatchIds() {
        for preset in ProfilePreset.allCases {
            let sourcesCount = preset.blocklistSources.count
            let idsCount = preset.blocklistSourceIds.count
            if sourcesCount != idsCount {
                Issue.record("Preset \(preset.displayName): blocklistSources count (\(sourcesCount)) != blocklistSourceIds count (\(idsCount))")
            }
        }
    }

    // MARK: - Minimum / Maximum Levels

    @Test("Essentials is the minimum level with fewest sources")
    func essentialsIsMinimumLevel() {
        let essentialsCount = ProfilePreset.essentials.blocklistSourceIds.count

        for preset in ProfilePreset.allCases where preset != .essentials {
            #expect(preset.blocklistSourceIds.count > essentialsCount)
        }
    }

    @Test("Kitchen Sink is the maximum level including all sources from all levels")
    func kitchenSinkIsMaximumLevel() {
        let kitchenSinkIds = Set(ProfilePreset.kitchenSink.blocklistSourceIds)
        let kitchenSinkCount = kitchenSinkIds.count

        // kitchenSink should have the most sources
        for preset in ProfilePreset.allCases where preset != .kitchenSink {
            #expect(preset.blocklistSourceIds.count < kitchenSinkCount)
        }

        // kitchenSink should include every ID from every other level
        for preset in ProfilePreset.allCases {
            let presetIds = Set(preset.blocklistSourceIds)
            #expect(presetIds.isSubset(of: kitchenSinkIds))
        }
    }

    // MARK: - Case Ordering

    @Test("Protection level case order is essentials through kitchenSink")
    func protectionLevelCaseOrder() {
        let allCases = ProfilePreset.allCases
        #expect(allCases.count == 5)

        #expect(allCases[0] == .essentials)
        #expect(allCases[1] == .familySafe)
        #expect(allCases[2] == .focusMode)
        #expect(allCases[3] == .privacyShield)
        #expect(allCases[4] == .kitchenSink)
    }

    @Test("Each successive level has strictly more sources")
    func strictlyIncreasingSourceCounts() {
        let allCases = ProfilePreset.allCases
        for i in 1..<allCases.count {
            let previousCount = allCases[i - 1].blocklistSourceIds.count
            let currentCount = allCases[i].blocklistSourceIds.count
            #expect(currentCount > previousCount)
        }
    }

    // MARK: - Uniqueness

    @Test("Blocklist source IDs are unique within each level")
    func blocklistSourceIDsAreUnique() {
        for preset in ProfilePreset.allCases {
            let ids = preset.blocklistSourceIds
            let uniqueIds = Set(ids)
            #expect(ids.count == uniqueIds.count)
        }
    }

    @Test("All presets have unique display names")
    func uniqueDisplayNames() {
        let names = ProfilePreset.allCases.map(\.displayName)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }

    @Test("All presets have unique color tags")
    func uniqueColorTags() {
        let colors = ProfilePreset.allCases.map(\.colorTag)
        let uniqueColors = Set(colors)
        #expect(colors.count == uniqueColors.count)
    }

    // MARK: - Identifiable

    @Test("Preset IDs match raw values")
    func presetIdsMatchRawValues() {
        for preset in ProfilePreset.allCases {
            #expect(preset.id == preset.rawValue)
        }
    }

    // MARK: - Profile Creation

    @Test("createProfile produces a valid Profile from a preset")
    func presetCreateProfile() {
        let entries = [
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["ads.example.com"]),
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["tracker.example.com"]),
        ]

        for preset in ProfilePreset.allCases {
            let profile = preset.createProfile(with: entries)

            #expect(profile.name == preset.displayName)
            #expect(profile.entries.count == entries.count)
            #expect(profile.isActive == false)
            #expect(profile.colorTag == preset.colorTag)

            // Source should be .merged with correct source count
            if case .merged(let sourceCount) = profile.source {
                #expect(sourceCount == preset.blocklistSourceIds.count)
            } else {
                Issue.record("Profile source should be .merged for preset \(preset.displayName), got \(profile.source)")
            }
        }
    }

    @Test("createProfile with empty entries produces empty profile")
    func presetCreateProfileEmpty() {
        let profile = ProfilePreset.essentials.createProfile(with: [])
        #expect(profile.entries.isEmpty)
        #expect(profile.name == "Essentials")
    }
}

// MARK: - PresetManager Tests

@Suite("PresetManager Tests")
struct PresetManagerTests {

    @Test("PresetManager shared instance exists")
    func sharedInstanceExists() async {
        // PresetManager is an actor with a shared singleton
        let manager = PresetManager.shared
        // Actor references are never nil; verify the type is correct
        #expect(type(of: manager) == PresetManager.self)
    }
}

// MARK: - PresetError Tests

@Suite("PresetError Tests")
struct PresetErrorTests {

    @Test("PresetError has localized descriptions")
    func errorDescriptions() {
        #expect(PresetError.invalidData.errorDescription != nil)
        #expect(PresetError.networkUnavailable.errorDescription != nil)
        #expect(PresetError.presetNotFound.errorDescription != nil)
    }

    @Test("PresetError descriptions are meaningful")
    func errorDescriptionsAreMeaningful() {
        let invalidDesc = PresetError.invalidData.errorDescription ?? ""
        #expect(invalidDesc.localizedCaseInsensitiveContains("invalid"))

        let networkDesc = PresetError.networkUnavailable.errorDescription ?? ""
        #expect(networkDesc.localizedCaseInsensitiveContains("network"))

        let notFoundDesc = PresetError.presetNotFound.errorDescription ?? ""
        #expect(notFoundDesc.localizedCaseInsensitiveContains("preset"))
    }
}

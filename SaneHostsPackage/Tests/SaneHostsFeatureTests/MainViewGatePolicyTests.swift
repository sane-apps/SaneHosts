import Foundation
@testable import SaneHostsFeature
import Testing

@Suite("MainView Gate Policy Tests")
struct MainViewGatePolicyTests {
    @Test("Basic users cannot open remote import from empty state")
    func basicCannotOpenRemoteImport() {
        #expect(MainViewGatePolicy.canOpenRemoteImport(isPro: false) == false)
    }

    @Test("Pro users can open remote import from empty state")
    func proCanOpenRemoteImport() {
        #expect(MainViewGatePolicy.canOpenRemoteImport(isPro: true))
    }

    @Test("Basic defaults to Essentials when no prior selection")
    func basicDefaultsToEssentials() {
        let essentials = Profile(id: UUID(), name: "Essentials")
        let strict = Profile(id: UUID(), name: "Strict")

        let selection = MainViewSelectionPolicy.initialSelection(
            profiles: [strict, essentials],
            isPro: false,
            currentSelection: []
        )

        #expect(selection == [essentials.id])
    }

    @Test("Existing valid selection is preserved on reload")
    func existingSelectionIsPreserved() {
        let essentials = Profile(id: UUID(), name: "Essentials")
        let strict = Profile(id: UUID(), name: "Strict")

        let selection = MainViewSelectionPolicy.initialSelection(
            profiles: [essentials, strict],
            isPro: false,
            currentSelection: [strict.id]
        )

        #expect(selection == [strict.id])
    }

    @Test("Falls back to active profile when Essentials missing")
    func fallsBackToActiveProfile() {
        let active = Profile(id: UUID(), name: "Custom", isActive: true)
        let other = Profile(id: UUID(), name: "Another")

        let selection = MainViewSelectionPolicy.initialSelection(
            profiles: [other, active],
            isPro: false,
            currentSelection: []
        )

        #expect(selection == [active.id])
    }
}

@Suite("Profile Store Bootstrap Policy Tests")
struct ProfileStoreBootstrapPolicyTests {
    @Test("Menu bar bootstrap loads when the shared store is still empty")
    func loadsWhenStoreIsEmpty() {
        #expect(ProfileStoreBootstrapPolicy.shouldLoad(profileCount: 0, isLoading: false))
    }

    @Test("Menu bar bootstrap does not double-load while a load is already running")
    func skipsWhileLoadIsRunning() {
        #expect(ProfileStoreBootstrapPolicy.shouldLoad(profileCount: 0, isLoading: true) == false)
    }

    @Test("Menu bar bootstrap does not reload once profiles are already available")
    func skipsWhenProfilesAlreadyLoaded() {
        #expect(ProfileStoreBootstrapPolicy.shouldLoad(profileCount: 1, isLoading: false) == false)
    }
}

@Suite("Profile Store Essentials Policy Tests")
struct ProfileStoreEssentialsPolicyTests {
    @Test("Creates Essentials when migration already created Existing Entries")
    func createsEssentialsAlongsideExistingEntries() {
        let existingEntries = Profile(name: "Existing Entries", source: .system)

        #expect(ProfileStoreEssentialsPolicy.needsEssentialsProfile(profiles: [existingEntries]))
    }

    @Test("Does not duplicate Essentials when it already exists")
    func doesNotDuplicateExistingEssentials() {
        let essentials = Profile(name: "Essentials")
        let existingEntries = Profile(name: "Existing Entries", source: .system)

        #expect(ProfileStoreEssentialsPolicy.needsEssentialsProfile(profiles: [existingEntries, essentials]) == false)
    }

    @Test("Essentials matching is case insensitive")
    func essentialsMatchingIsCaseInsensitive() {
        let essentials = Profile(name: "essentials")

        #expect(ProfileStoreEssentialsPolicy.needsEssentialsProfile(profiles: [essentials]) == false)
    }
}

@Suite("Entry Row Layout Policy Tests")
struct EntryRowLayoutPolicyTests {
    @Test("IPv4 addresses stay on one line in the entry table")
    func ipAddressesStayOnOneLine() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let designSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/DesignSystem/DesignSystem.swift"))
        let detailSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/ProfileDetailView.swift"))

        #expect(designSource.contains(".lineLimit(1)"))
        #expect(designSource.contains(".fixedSize(horizontal: true, vertical: false)"))
        #expect(detailSource.contains(".frame(width: 140, alignment: .leading)"))
    }
}

@Suite("Customer UI Manifest Policy Tests")
struct CustomerUIManifestPolicyTests {
    @Test("Bulk entry actions require visual evidence")
    func bulkEntryActionsRequireVisualEvidence() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repoRoot = packageRoot.deletingLastPathComponent()
        let manifest = try String(contentsOf: repoRoot.appendingPathComponent("Tests/CustomerUIActions.yml"))

        guard let bulkStart = manifest.range(of: "- id: bulk-entry-actions"),
              let settingsStart = manifest.range(of: "- id: settings-license-about-update-support") else {
            Issue.record("Customer UI manifest is missing the expected bulk/settings action boundaries")
            return
        }

        let bulkBlock = manifest[bulkStart.lowerBound..<settingsStart.lowerBound]
        #expect(bulkBlock.contains("required_evidence_types:"))
        #expect(bulkBlock.contains("- screenshot"))
        #expect(bulkBlock.contains("- fixture"))
        #expect(bulkBlock.contains("- state_receipt"))
    }
}

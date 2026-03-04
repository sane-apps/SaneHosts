import Testing
@testable import SaneHostsFeature
import Foundation

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

import Foundation
@testable import SaneHostsFeature
import Testing

/// Regression (2026-07-14, customer report): after activating a paid license
/// the sidebar Advanced Tools header kept its closed padlock because the icon
/// was hardcoded decoration. The header icon must track license state.
struct ProSectionIconTests {
    @Test("Advanced Tools header padlock opens with paid access")
    func padlockOpensWhenPro() {
        #expect(ProFeature.sectionIcon(isPro: true) == "lock.open.fill")
    }

    @Test("Advanced Tools header padlock stays closed while features are gated")
    func padlockStaysClosedWhenLocked() {
        #expect(ProFeature.sectionIcon(isPro: false) == "lock.fill")
    }

    @Test("Advanced Tools header passes the live license state to the padlock")
    func sidebarPassesLiveLicenseStateToPadlock() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let layoutSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/MainView+Layout.swift")
        )

        #expect(layoutSource.contains("Image(systemName: ProFeature.sectionIcon(isPro: licenseService.isPro))"))
        #expect(!layoutSource.contains("Image(systemName: ProFeature.sectionIcon(isPro: false))"))
    }
}

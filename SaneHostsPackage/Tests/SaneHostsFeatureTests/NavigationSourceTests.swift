import Foundation
import Testing

struct NavigationSourceTests {
    @Test("SaneHosts settings actions use the shared opener across dock and menu bar")
    func saneHostsSettingsActionsUseSharedOpener() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let appSource = try String(
            contentsOf: projectRoot.appendingPathComponent("SaneHosts/SaneHostsApp.swift"),
            encoding: .utf8
        )

        #expect(appSource.contains("final class SettingsActionStorage"))
        #expect(appSource.contains("SettingsActionStorage.shared.showSettings()"))
        #expect(appSource.contains("SettingsActionStorage.shared.capture(openSettings)"))
        #expect(!appSource.contains("SettingsLink {"))
    }
}

import Foundation
import Testing

struct NavigationSourceTests {
    @Test("SaneUI dependency defaults to the release-tested revision")
    func saneUIDependencyDefaultsToPinnedRevision() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let packageSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        #expect(packageSource.contains("SANEHOSTS_USE_LOCAL_SANEUI"))
        #expect(packageSource.contains("revision: \"0133badcb1d17a5805a34a0c251d7636de3d1a21\""))
        #expect(!packageSource.contains("if FileManager.default.fileExists(atPath: localSaneUIPath)"))
    }

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
        #expect(appSource.contains("SettingsActionStorage.shared.showSettings(tab: .license)"))
        #expect(appSource.contains("SettingsActionStorage.shared.showSettings(tab: .about)"))
        #expect(appSource.contains("SettingsActionStorage.shared.capture(openSettings)"))
        #expect(appSource.contains("SaneStandardMenu.openAppItem"))
        #expect(appSource.contains("SaneStandardMenu.addCoreUtilityItems"))
        #expect(appSource.contains("directUpdateAction"))
        #expect(!appSource.contains("SettingsLink {"))
    }

    @Test("SaneHosts settings supports queued license and about tab routing")
    func saneHostsSettingsSupportsQueuedTabRouting() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let settingsSource = try String(
            contentsOf: projectRoot.appendingPathComponent("SaneHosts/SettingsView.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: projectRoot.appendingPathComponent("SaneHosts/SaneHostsApp.swift"),
            encoding: .utf8
        )

        #expect(settingsSource.contains("enum SaneHostsSettingsTab"))
        #expect(settingsSource.contains("@State private var selectedTab: SaneHostsSettingsTab?"))
        #expect(settingsSource.contains("selection: $selectedTab"))
        #expect(settingsSource.contains("NotificationCenter.default.publisher(for: .showSettingsTab)"))
        #expect(appSource.contains("static let showSettingsTab"))
        #expect(appSource.contains("NotificationCenter.default.post(name: .showSettingsTab, object: tab)"))
    }
}

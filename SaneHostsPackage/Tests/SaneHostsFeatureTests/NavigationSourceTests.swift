import Foundation
import Testing

struct NavigationSourceTests {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

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
        #expect(packageSource.contains("revision: \"d8005a1133e237e45a2216ef0b9d785e725f78ba\""))
        #expect(!packageSource.contains("if FileManager.default.fileExists(atPath: localSaneUIPath)"))
    }

    @Test("Every tracked package resolution uses the release-tested SaneUI revision")
    func trackedPackageResolutionsUsePinnedSaneUIRevision() throws {
        let resolvedPaths = [
            "SaneHosts.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            "SaneHosts.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        ]
        let expectedRevision = "\"revision\" : \"d8005a1133e237e45a2216ef0b9d785e725f78ba\""

        for relativePath in resolvedPaths {
            let resolvedSource = try String(
                contentsOf: projectRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )

            #expect(resolvedSource.contains(expectedRevision))
        }
    }

    @Test("Current customer copy uses the trial then purchase model")
    func currentCustomerCopyUsesTrialThenPurchaseModel() throws {
        let paths = [
            "AGENTS.md", "README.md", "PRIVACY.md", "SaneHosts/SaneHostsApp.swift",
            "SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift",
            "SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Layout.swift",
            "SaneHostsPackage/Sources/SaneHostsFeature/Views/MainViewComponents.swift",
            "SaneHostsPackage/Sources/SaneHostsFeature/Views/ProfileDetailView.swift",
            "SaneHostsPackage/Sources/SaneHostsFeature/DesignSystem/DesignSystem.swift",
            "SaneHostsPackage/Sources/SaneHostsFeature/Views/PresetViews.swift",
            "Tests/CustomerUIActions.yml", "website/index.html", "website/privacy.html"
        ]
        let copy = try paths.map {
            try String(contentsOf: projectRoot.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n")
        let retired = [
            "Basic is free", "Basic vs Pro", "14-day Pro trial", "Buy Pro",
            "PRO FEATURES", "Pro feature —", "Basic remains included", "Keep Pro",
            "SaneHosts Pro", "Start Full Pro Trial", "Full Pro Trial",
            "Every Pro feature", "Pro is required", "14 days of Pro", "Pro purchases",
            "free profile"
        ]

        #expect(copy.contains("14-day trial"))
        #expect(copy.contains("Buy SaneHosts once"))
        #expect(copy.contains("ADVANCED TOOLS"))
        #expect(copy.contains("No spying"))
        #expect(copy.contains("No subscription"))
        #expect(copy.contains("Actively maintained"))
        #expect(copy.contains("Color.saneAccent.opacity"))
        #expect(!copy.contains("static let saneAccent ="))
        for phrase in retired {
            #expect(!copy.contains(phrase))
        }
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

    @Test("SaneHosts owns its direct Sparkle settings UI")
    func saneHostsOwnsDirectSparkleSettingsUI() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let sparkleSource = try String(
            contentsOf: projectRoot.appendingPathComponent("SaneHosts/SaneSparkleRow.swift"),
            encoding: .utf8
        )

        #expect(sparkleSource.contains("struct SaneSparkleRow"))
        #expect(sparkleSource.contains("enum SaneSparkleCheckFrequency"))
        #expect(sparkleSource.contains("Check for updates automatically"))
    }
}

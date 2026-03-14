import Foundation
import Testing

struct AppStoreReviewGuardrailTests {
    @Test("App Store entitlements do not request Apple Events")
    func appStoreEntitlementsDoNotRequestAppleEvents() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlements = try String(
            contentsOf: projectRoot.appendingPathComponent("Config/SaneHosts-AppStore.entitlements"),
            encoding: .utf8
        )

        #expect(entitlements.contains("com.apple.security.automation.apple-events") == false)
    }

    @Test("App Store review notes describe helper-only StoreKit flow")
    func appStoreReviewNotesDescribeHelperOnlyStoreKitFlow() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try String(contentsOf: projectRoot.appendingPathComponent(".saneprocess"), encoding: .utf8)

        #expect(manifest.contains("privileged helper"))
        #expect(manifest.contains("There is no external checkout and no license key flow in the App Store build."))
        #expect(manifest.contains("This build does not use Apple Events or AppleScript."))
    }

    @Test("App Store plist omits Apple Events usage description")
    func appStorePlistOmitsAppleEventsUsageDescription() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plist = try String(
            contentsOf: projectRoot.appendingPathComponent("SaneHosts/Info-AppStore.plist"),
            encoding: .utf8
        )

        #expect(plist.contains("NSAppleEventsUsageDescription") == false)
    }

    @Test("Shared package does not rely on APP_STORE compile flags")
    func sharedPackageDoesNotUseAppStoreCompileFlags() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let contentView = try String(
            contentsOf: projectRoot.appendingPathComponent("SaneHostsPackage/Sources/SaneHostsFeature/ContentView.swift"),
            encoding: .utf8
        )
        let mainView = try String(
            contentsOf: projectRoot.appendingPathComponent("SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift"),
            encoding: .utf8
        )

        #expect(contentView.contains("#if APP_STORE") == false)
        #expect(mainView.contains("#if APP_STORE") == false)
    }

    @Test("Shared package does not compile AppleScript fallback")
    func sharedPackageDoesNotCompileAppleScriptFallback() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hostsService = try String(
            contentsOf: projectRoot.appendingPathComponent("SaneHostsPackage/Sources/SaneHostsFeature/Services/HostsService.swift"),
            encoding: .utf8
        )

        #expect(hostsService.contains("NSAppleScript") == false)
        #expect(hostsService.contains("with administrator privileges") == false)
    }
}

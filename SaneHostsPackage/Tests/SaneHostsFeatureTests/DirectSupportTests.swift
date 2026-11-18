import Foundation
@testable import SaneHostsFeature
import Testing

@MainActor
struct DirectSupportTests {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Direct build supplies the Donate copy the About screen shows")
    func directBuildSuppliesDonateSupportCopy() throws {
        SaneDirectSupportCopy.current = nil
        SaneHostsDirectSupport.install()

        let copy = try #require(SaneDirectSupportCopy.current)
        #expect(copy.aboutRowTitle == "Donate")
        #expect(copy.buttonTitle == "Donate")
        #expect(copy.buttonHelp == "Donate on GitHub Sponsors")
        #expect(copy.accessibilityLabel == "Donate")
        #expect(copy.destinationURL.absoluteString == "https://github.com/sponsors/MrSaneApps")
    }

    @Test("Direct launch installs the Donate copy before anything else")
    func directLaunchInstallsDonateSupportCopy() throws {
        let appSource = try String(
            contentsOf: projectRoot.appendingPathComponent("SaneHosts/SaneHostsApp.swift"),
            encoding: .utf8
        )
        let supportSource = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "SaneHostsPackage/Sources/SaneHostsFeature/DirectDistributionSupport.swift"
            ),
            encoding: .utf8
        )
        let afterLaunch = appSource.components(separatedBy: "func applicationDidFinishLaunching").dropFirst().first ?? ""
        let launchBody = afterLaunch.components(separatedBy: "\n    private func ").first ?? ""
        let guardAt = try #require(launchBody.range(of: "#if !APP_STORE && !SETAPP"))
        let installAt = try #require(launchBody.range(of: "SaneHostsDirectSupport.install()"))
        let moverAt = try #require(launchBody.range(of: "SaneApplicationMover.moveToApplicationsFolderIfNeeded"))

        #expect(guardAt.lowerBound < installAt.lowerBound)
        #expect(installAt.lowerBound < moverAt.lowerBound)
        #expect(supportSource.hasPrefix("#if os(macOS) && !APP_STORE && !SETAPP"))
    }
}

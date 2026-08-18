// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
let localSaneUIPath = packageDirectory
    .appendingPathComponent("../../../infra/SaneUI")
    .standardizedFileURL.path
let saneUIDependency: Package.Dependency = {
    if ProcessInfo.processInfo.environment["SANEHOSTS_USE_LOCAL_SANEUI"] == "1",
       FileManager.default.fileExists(atPath: localSaneUIPath) {
        return .package(path: localSaneUIPath)
    }

    return .package(url: "https://github.com/sane-apps/SaneUI.git", revision: "387e29166b1a2b9502840ea0bd09b50fa199e873")
}()

let package = Package(
    name: "SaneHostsFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "SaneHostsFeature",
            targets: ["SaneHostsFeature"]
        )
    ],
    dependencies: [
        saneUIDependency
    ],
    targets: [
        .target(
            name: "SaneHostsFeature",
            dependencies: ["SaneUI"]
        ),
        .testTarget(
            name: "SaneHostsFeatureTests",
            dependencies: [
                "SaneHostsFeature"
            ]
        )
    ]
)

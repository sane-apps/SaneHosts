// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
        .package(path: "../../../infra/SaneUI")
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

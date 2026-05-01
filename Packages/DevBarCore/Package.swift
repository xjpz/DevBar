// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DevBarCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "DevBarCore",
            targets: ["DevBarCore"]
        ),
    ],
    targets: [
        .target(
            name: "DevBarCore"
        ),
        .testTarget(
            name: "DevBarCoreTests",
            dependencies: ["DevBarCore"]
        ),
    ]
)

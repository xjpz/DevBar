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
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", "0.12.0"..<"0.13.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(
            name: "DevBarCore",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                "OpenSSHBcrypt",
            ]
        ),
        .target(
            name: "OpenSSHBcrypt"
        ),
        .testTarget(
            name: "DevBarCoreTests",
            dependencies: ["DevBarCore"]
        ),
    ]
)

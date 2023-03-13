// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftCommand",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SwiftCommand",
            targets: ["SwiftCommand"]),
        .executable(name: "swift-command", targets: ["swift-command"])

    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-system", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "SwiftCommand",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system")
            ]
        ),
        .executableTarget(name: "swift-command", dependencies: ["SwiftCommand"]),
        .testTarget(
            name: "SwiftCommandTests",
            dependencies: ["SwiftCommand"]
        ),
    ]
)

// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftCommand",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SwiftCommand",
            targets: ["SwiftCommand"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
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

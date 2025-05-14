// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XCodeFreeze_alpha3",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "XCodeFreeze_alpha3",
            targets: ["XCodeFreeze_alpha3"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.8.2")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "XCodeFreeze_alpha3",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ]),
        .testTarget(
            name: "XCodeFreeze_alpha3Tests",
            dependencies: ["XCodeFreeze_alpha3"]
        ),
    ]
)

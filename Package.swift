// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Openbird",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OpenbirdKit",
            targets: ["OpenbirdKit"]
        ),
        .executable(
            name: "OpenbirdApp",
            targets: ["OpenbirdApp"]
        ),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite"
        ),
        .target(
            name: "OpenbirdKit",
            dependencies: ["CSQLite"]
        ),
        .executableTarget(
            name: "OpenbirdApp",
            dependencies: ["OpenbirdKit"]
        ),
        .testTarget(
            name: "OpenbirdKitTests",
            dependencies: ["OpenbirdKit"]
        ),
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SpaceRenamerCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SpaceRenamerCore",
            targets: ["SpaceRenamerCore"]
        ),
    ],
    targets: [
        .target(
            name: "SpaceRenamerCore"
        ),
        .testTarget(
            name: "SpaceRenamerCoreTests",
            dependencies: ["SpaceRenamerCore"],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)

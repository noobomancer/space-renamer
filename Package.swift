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
    // Concurrency: the stateful Core types (NameStore, SpaceMonitor, SwitcherEngine)
    // and OrdinalLookup are @MainActor-isolated — the app is an AppKit menu-bar app
    // driven entirely from the main thread. Swift 5 language mode (tools 5.10) is
    // retained for now; full Swift 6 strict-concurrency adoption is deferred until
    // the Xcode app target is created (tracked Phase B item).
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

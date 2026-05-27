// swift-tools-version: 6.0
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
    // Concurrency: stateful Core types (NameStore, SpaceMonitor, SwitcherEngine)
    // and OrdinalLookup are @MainActor-isolated; pure/stateless types stay
    // non-isolated (D9). Swift 6 strict concurrency is enabled per-target via
    // .swiftLanguageMode(.v6) — see *Design Revision 2026-05-26* (Phase B #26).
    targets: [
        .target(
            name: "SpaceRenamerCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SpaceRenamerCoreTests",
            dependencies: ["SpaceRenamerCore"],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)

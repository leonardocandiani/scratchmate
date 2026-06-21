// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScratchMate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "scratchmate", targets: ["ScratchMate"]),
        .library(name: "ScratchMateCore", targets: ["ScratchMateCore"]),
    ],
    dependencies: [
        // Auto-update framework. The Updater wraps it behind `canImport(Sparkle)`.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Native macOS app: window, hotkey, palette, URL scheme.
        .executableTarget(
            name: "ScratchMate",
            dependencies: [
                "ScratchMateCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [
                // AppKit app: the whole module runs on the main actor by default.
                .defaultIsolation(MainActor.self)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("WebKit"),
            ]
        ),
        // Notes model, SQLite storage, commands. Zero external dependencies.
        .target(
            name: "ScratchMateCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ScratchMateCoreTests",
            dependencies: ["ScratchMateCore"]
        ),
    ]
)

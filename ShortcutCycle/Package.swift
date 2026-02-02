// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShortcutCycle",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ShortcutCycle", targets: ["ShortcutCycle"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "ShortcutCycleCore",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "ShortcutCycle",
            sources: [
                "Models/AppGroup.swift",
                "Models/AppItem.swift",
                "Models/BackupRetention.swift",
                "Models/GroupStore.swift",
                "Models/SettingsExport.swift",
                "Models/KeyboardShortcutsNames.swift"
            ]
        ),
        .executableTarget(
            name: "ShortcutCycle",
            dependencies: [
                "ShortcutCycleCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "ShortcutCycle",
            exclude: [
                "Models/AppGroup.swift",
                "Models/AppItem.swift",
                "Models/BackupRetention.swift",
                "Models/GroupStore.swift",
                "Models/SettingsExport.swift",
                "Models/KeyboardShortcutsNames.swift"
            ]
        ),
        .testTarget(
            name: "ShortcutCycleTests",
            dependencies: ["ShortcutCycleCore"],
            path: "ShortcutCycleTests"
        )
    ]
)

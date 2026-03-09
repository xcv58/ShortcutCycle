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
            path: "ShortcutCycle/Models",
            sources: [
                "AppGroup.swift",
                "AppItem.swift",
                "BackupDiff.swift",
                "BackupRetention.swift",
                "GroupStore.swift",
                "HUDAppItem.swift",
                "SettingsExport.swift",
                "KeyboardShortcutsNames.swift",
                "URLCommandFileValidation.swift",
                "URLRouterLogic.swift",
                "URLScheme.swift"
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
                "Info.plist",
                "Models",
                "ShortcutCycle.entitlements"
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ShortcutCycleTests",
            dependencies: [
                "ShortcutCycleCore",
                "ShortcutCycle"
            ],
            path: "ShortcutCycleTests"
        )
    ]
)

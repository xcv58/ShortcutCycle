// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShortcutCycle",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ShortcutCycle", targets: ["ShortcutCycle"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "ShortcutCycle",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "ShortcutCycle"
        )
    ]
)

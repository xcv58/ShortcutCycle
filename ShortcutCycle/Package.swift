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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ShortcutCycle",
            dependencies: [],
            path: "ShortcutCycle"
        )
    ]
)

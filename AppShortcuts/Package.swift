// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppShortcuts",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AppShortcuts", targets: ["AppShortcuts"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AppShortcuts",
            dependencies: [],
            path: "AppShortcuts"
        )
    ]
)

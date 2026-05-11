#if DEBUG
import AppKit
import Foundation
import UniformTypeIdentifiers
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

enum ScreenshotFixtureLibrary {
    private struct FixtureApp {
        let name: String
        let bundleID: String
    }

    private struct FixtureGroup {
        let key: ScreenshotFixtureGroupKey
        let id: UUID
        let name: String
        let apps: [FixtureApp]
        let isEnabled: Bool
        let openAppIfNeeded: Bool
    }

    private static let fixtureGroups: [FixtureGroup] = [
        FixtureGroup(
            key: .info,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: "Info",
            apps: [
                .init(name: "Weather", bundleID: "com.apple.weather"),
                .init(name: "Maps", bundleID: "com.apple.Maps"),
                .init(name: "Stocks", bundleID: "com.apple.stocks"),
                .init(name: "News", bundleID: "com.apple.news")
            ],
            isEnabled: true,
            openAppIfNeeded: true
        ),
        FixtureGroup(
            key: .communication,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            name: "Communication",
            apps: [
                .init(name: "Messages", bundleID: "com.apple.MobileSMS"),
                .init(name: "FaceTime", bundleID: "com.apple.FaceTime"),
                .init(name: "Mail", bundleID: "com.apple.mail"),
                .init(name: "Contacts", bundleID: "com.apple.AddressBook")
            ],
            isEnabled: true,
            openAppIfNeeded: false
        ),
        FixtureGroup(
            key: .productivity,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            name: "Productivity",
            apps: [
                .init(name: "Calendar", bundleID: "com.apple.iCal"),
                .init(name: "Reminders", bundleID: "com.apple.reminders"),
                .init(name: "Notes", bundleID: "com.apple.Notes"),
                .init(name: "Freeform", bundleID: "com.apple.freeform"),
                .init(name: "Preview", bundleID: "com.apple.Preview")
            ],
            isEnabled: true,
            openAppIfNeeded: false
        ),
        FixtureGroup(
            key: .utilities,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            name: "Utilities",
            apps: [
                .init(name: "Terminal", bundleID: "com.apple.Terminal"),
                .init(name: "Activity Monitor", bundleID: "com.apple.ActivityMonitor"),
                .init(name: "Console", bundleID: "com.apple.Console"),
                .init(name: "System Settings", bundleID: "com.apple.systempreferences"),
                .init(name: "Calculator", bundleID: "com.apple.calculator"),
                .init(name: "Shortcuts", bundleID: "com.apple.shortcuts"),
                .init(name: "App Store", bundleID: "com.apple.AppStore"),
                .init(name: "QuickTime Player", bundleID: "com.apple.QuickTimePlayerX")
            ],
            isEnabled: true,
            openAppIfNeeded: true
        ),
        FixtureGroup(
            key: .media,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            name: "Media",
            apps: [
                .init(name: "Music", bundleID: "com.apple.Music"),
                .init(name: "TV", bundleID: "com.apple.TV"),
                .init(name: "Podcasts", bundleID: "com.apple.podcasts"),
                .init(name: "Photos", bundleID: "com.apple.Photos"),
                .init(name: "Books", bundleID: "com.apple.iBooksX")
            ],
            isEnabled: false,
            openAppIfNeeded: false
        ),
        FixtureGroup(
            key: .manyApps,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
            name: "Many Apps",
            apps: [
                .init(name: "Weather", bundleID: "com.apple.weather"),
                .init(name: "Maps", bundleID: "com.apple.Maps"),
                .init(name: "Music", bundleID: "com.apple.Music"),
                .init(name: "TV", bundleID: "com.apple.TV"),
                .init(name: "Photos", bundleID: "com.apple.Photos"),
                .init(name: "Notes", bundleID: "com.apple.Notes"),
                .init(name: "Terminal", bundleID: "com.apple.Terminal"),
                .init(name: "System Settings", bundleID: "com.apple.systempreferences"),
                .init(name: "App Store", bundleID: "com.apple.AppStore"),
                .init(name: "Preview", bundleID: "com.apple.Preview")
            ],
            isEnabled: true,
            openAppIfNeeded: true
        )
    ]

    static func makeGroups() -> [AppGroup] {
        fixtureGroups.map { fixtureGroup in
            AppGroup(
                id: fixtureGroup.id,
                name: fixtureGroup.name,
                apps: fixtureGroup.apps.map(makeAppItem),
                isEnabled: fixtureGroup.isEnabled,
                openAppIfNeeded: fixtureGroup.openAppIfNeeded,
                lastModified: Date(timeIntervalSince1970: 1_735_689_600)
            )
        }
    }

    static func groupID(for key: ScreenshotFixtureGroupKey) -> UUID? {
        fixtureGroups.first(where: { $0.key == key })?.id
    }

    static func hudItems(for key: ScreenshotFixtureGroupKey) -> [HUDAppItem] {
        guard let group = fixtureGroups.first(where: { $0.key == key }) else { return [] }
        return group.apps.map { app in
            HUDAppItem(
                id: app.bundleID,
                name: app.name,
                icon: icon(for: app.bundleID),
                isRunning: true
            )
        }
    }

    static func hudCaptureState(
        for scene: ScreenshotScene,
        key: ScreenshotFixtureGroupKey
    ) -> (items: [HUDAppItem], activeItemID: String, shortcut: String?) {
        let items = hudItems(for: key)
        let activeItemID: String

        switch scene {
        case .hudGrid:
            activeItemID = items.dropFirst(3).first?.id ?? items.first?.id ?? ""
        default:
            activeItemID = items.first?.id ?? ""
        }

        let shortcut: String?
        if let index = items.firstIndex(where: { $0.id == activeItemID }) {
            shortcut = "⌥\(index + 1)"
        } else {
            shortcut = nil
        }

        return (items, activeItemID, shortcut)
    }

    static func menuRunningBundleIDs() -> Set<String> {
        Set(
            fixtureGroups
                .filter(\.isEnabled)
                .flatMap { group in group.apps.map(\.bundleID) }
        )
    }

    static func makeQuickAddOverrideApps() -> [AppItem] {
        var seenBundleIDs = Set<String>()
        return fixtureGroups
            .flatMap(\.apps)
            .filter { seenBundleIDs.insert($0.bundleID).inserted }
            .map(makeAppItem)
            .sorted {
                let lhs = $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                let rhs = $1.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                if lhs == rhs {
                    return $0.bundleIdentifier < $1.bundleIdentifier
                }
                return lhs < rhs
            }
    }

    static func makeExport(groups: [AppGroup], theme: AppTheme, language: String) -> SettingsExport {
        SettingsExport(
            groups: groups,
            settings: AppSettings(
                showHUD: true,
                showShortcutInHUD: true,
                selectedLanguage: language,
                appTheme: theme.rawValue
            ),
            shortcuts: ScreenshotRuntime.shortcutDataMap(for: groups)
        )
    }

    @MainActor
    static func writeBackupFixtures(
        into store: GroupStore,
        groups: [AppGroup],
        language: String,
        theme: AppTheme
    ) {
        let fileManager = FileManager.default
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        try? fileManager.removeItem(at: store.backupDirectory)
        try? fileManager.createDirectory(at: store.backupDirectory, withIntermediateDirectories: true)

        let comparisonGroups = groups.enumerated().map { index, group -> AppGroup in
            guard index == 0 else { return group }
            var updatedGroup = group
            updatedGroup.apps = Array(group.apps.dropLast())
            return updatedGroup
        }

        let exports: [(name: String, export: SettingsExport, createdAt: Date)] = [
            (
                "backup 2026-02-02 17-46-00.json",
                makeExport(groups: comparisonGroups, theme: theme == .dark ? .light : .dark, language: language),
                Date(timeIntervalSince1970: 1_770_074_760)
            ),
            (
                "backup 2026-02-02 17-52-00.json",
                makeExport(groups: groups, theme: theme, language: language),
                Date(timeIntervalSince1970: 1_770_075_120)
            )
        ]

        for exportFile in exports {
            let fileURL = store.backupDirectory.appendingPathComponent(exportFile.name)
            guard let data = try? encoder.encode(exportFile.export) else { continue }
            try? data.write(to: fileURL, options: .atomic)
            try? fileManager.setAttributes([.creationDate: exportFile.createdAt], ofItemAtPath: fileURL.path)
        }
    }

    private static func makeAppItem(from definition: FixtureApp) -> AppItem {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: definition.bundleID)
        return AppItem(
            bundleIdentifier: definition.bundleID,
            name: definition.name,
            iconPath: appURL?.path
        )
    }

    private static func icon(for bundleID: String) -> NSImage {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
#endif

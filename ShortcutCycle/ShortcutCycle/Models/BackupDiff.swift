import Foundation

/// Status of a diffed item
public enum DiffStatus: Equatable {
    case added
    case removed
    case modified
    case unchanged
}

/// Change to a single app within a group
public struct AppChange: Identifiable {
    public let id = UUID()
    public let appName: String
    public let bundleIdentifier: String
    public let status: DiffStatus
}

/// Change to a group
public struct GroupDiff: Identifiable {
    public let id: UUID
    public let groupName: String
    public let status: DiffStatus
    public let appChanges: [AppChange]
}

/// Change to a setting
public struct SettingChange: Identifiable {
    public let id = UUID()
    public let key: String
    public let oldValue: String
    public let newValue: String
}

/// Result of comparing two backup snapshots
public struct BackupDiff {
    public let groupDiffs: [GroupDiff]
    public let settingChanges: [SettingChange]

    public var hasChanges: Bool {
        groupDiffs.contains(where: { $0.status != .unchanged }) ||
        !settingChanges.isEmpty
    }

    /// Compute diff between two SettingsExport snapshots
    public static func compute(before: SettingsExport, after: SettingsExport) -> BackupDiff {
        let groupDiffs = computeGroupDiffs(before: before.groups, after: after.groups)
        let settingChanges = computeSettingChanges(before: before.settings, after: after.settings)
        return BackupDiff(groupDiffs: groupDiffs, settingChanges: settingChanges)
    }

    private static func computeGroupDiffs(before: [AppGroup], after: [AppGroup]) -> [GroupDiff] {
        let beforeMap = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let afterMap = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })

        var diffs: [GroupDiff] = []

        // Groups in after
        for group in after {
            if let old = beforeMap[group.id] {
                let appChanges = computeAppChanges(before: old.apps, after: group.apps)
                let nameChanged = old.name != group.name
                let status: DiffStatus = (nameChanged || appChanges.contains(where: { $0.status != .unchanged })) ? .modified : .unchanged
                diffs.append(GroupDiff(id: group.id, groupName: group.name, status: status, appChanges: appChanges))
            } else {
                let appChanges = group.apps.map { AppChange(appName: $0.name, bundleIdentifier: $0.bundleIdentifier, status: .added) }
                diffs.append(GroupDiff(id: group.id, groupName: group.name, status: .added, appChanges: appChanges))
            }
        }

        // Groups removed (in before but not after)
        for group in before where afterMap[group.id] == nil {
            let appChanges = group.apps.map { AppChange(appName: $0.name, bundleIdentifier: $0.bundleIdentifier, status: .removed) }
            diffs.append(GroupDiff(id: group.id, groupName: group.name, status: .removed, appChanges: appChanges))
        }

        return diffs
    }

    private static func computeAppChanges(before: [AppItem], after: [AppItem]) -> [AppChange] {
        let beforeMap = Dictionary(uniqueKeysWithValues: before.map { ($0.bundleIdentifier, $0) })
        let afterMap = Dictionary(uniqueKeysWithValues: after.map { ($0.bundleIdentifier, $0) })

        var changes: [AppChange] = []

        for app in after {
            if beforeMap[app.bundleIdentifier] != nil {
                changes.append(AppChange(appName: app.name, bundleIdentifier: app.bundleIdentifier, status: .unchanged))
            } else {
                changes.append(AppChange(appName: app.name, bundleIdentifier: app.bundleIdentifier, status: .added))
            }
        }

        for app in before where afterMap[app.bundleIdentifier] == nil {
            changes.append(AppChange(appName: app.name, bundleIdentifier: app.bundleIdentifier, status: .removed))
        }

        return changes
    }

    private static func computeSettingChanges(before: AppSettings?, after: AppSettings?) -> [SettingChange] {
        let b = before ?? AppSettings(showHUD: true, showShortcutInHUD: true)
        let a = after ?? AppSettings(showHUD: true, showShortcutInHUD: true)

        var changes: [SettingChange] = []

        if b.showHUD != a.showHUD {
            changes.append(SettingChange(key: "Show HUD", oldValue: "\(b.showHUD)", newValue: "\(a.showHUD)"))
        }
        if b.showShortcutInHUD != a.showShortcutInHUD {
            changes.append(SettingChange(key: "Show Shortcut in HUD", oldValue: "\(b.showShortcutInHUD)", newValue: "\(a.showShortcutInHUD)"))
        }
        if (b.selectedLanguage ?? "system") != (a.selectedLanguage ?? "system") {
            changes.append(SettingChange(key: "Language", oldValue: b.selectedLanguage ?? "system", newValue: a.selectedLanguage ?? "system"))
        }
        if (b.appTheme ?? "system") != (a.appTheme ?? "system") {
            changes.append(SettingChange(key: "Theme", oldValue: b.appTheme ?? "system", newValue: a.appTheme ?? "system"))
        }

        return changes
    }
}

import Foundation
import KeyboardShortcuts

/// Status of a diffed item
public enum DiffStatus: Equatable {
    case added
    case removed
    case modified
    case unchanged
}

/// Change to a single app within a group
public struct AppChange: Identifiable {
    public let id: UUID
    public let appName: String
    public let oldAppName: String?
    public let bundleIdentifier: String
    public let status: DiffStatus

    public init(appName: String, bundleIdentifier: String, status: DiffStatus, oldAppName: String? = nil) {
        self.id = UUID()
        self.appName = appName
        self.oldAppName = oldAppName
        self.bundleIdentifier = bundleIdentifier
        self.status = status
    }
}

/// Change to a group
public struct GroupDiff: Identifiable {
    public let id: UUID
    public let groupName: String
    public let status: DiffStatus
    public let groupChanges: [SettingChange]
    public let appChanges: [AppChange]

    public init(
        id: UUID,
        groupName: String,
        status: DiffStatus,
        groupChanges: [SettingChange] = [],
        appChanges: [AppChange]
    ) {
        self.id = id
        self.groupName = groupName
        self.status = status
        self.groupChanges = groupChanges
        self.appChanges = appChanges
    }
}

/// Change to a setting
public struct SettingChange: Identifiable {
    public let id: UUID
    public let key: String
    public let oldValue: String
    public let newValue: String

    public init(key: String, oldValue: String, newValue: String) {
        self.id = UUID()
        self.key = key
        self.oldValue = oldValue
        self.newValue = newValue
    }
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
        let groupDiffs = computeGroupDiffs(
            before: before.groups,
            after: after.groups,
            beforeShortcuts: before.shortcuts,
            afterShortcuts: after.shortcuts
        )
        let settingChanges = computeSettingChanges(before: before.settings, after: after.settings)
        return BackupDiff(groupDiffs: groupDiffs, settingChanges: settingChanges)
    }

    private static func computeGroupDiffs(
        before: [AppGroup],
        after: [AppGroup],
        beforeShortcuts: [String: ShortcutData]?,
        afterShortcuts: [String: ShortcutData]?
    ) -> [GroupDiff] {
        let beforeMap = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let afterMap = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        let beforeShortcutMap = normalizedShortcutMap(beforeShortcuts)
        let afterShortcutMap = normalizedShortcutMap(afterShortcuts)

        var diffs: [GroupDiff] = []

        // Groups in after
        for group in after {
            if let old = beforeMap[group.id] {
                let appChanges = computeAppChanges(before: old.apps, after: group.apps)
                let groupChanges = computeGroupChanges(
                    before: old,
                    after: group,
                    beforeShortcut: beforeShortcutMap[group.id],
                    afterShortcut: afterShortcutMap[group.id]
                )
                let status: DiffStatus = (!groupChanges.isEmpty || appChanges.contains(where: { $0.status != .unchanged })) ? .modified : .unchanged
                diffs.append(
                    GroupDiff(
                        id: group.id,
                        groupName: group.name,
                        status: status,
                        groupChanges: groupChanges,
                        appChanges: appChanges
                    )
                )
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

    private static func computeGroupChanges(
        before: AppGroup,
        after: AppGroup,
        beforeShortcut: ShortcutData?,
        afterShortcut: ShortcutData?
    ) -> [SettingChange] {
        var changes: [SettingChange] = []

        if before.name != after.name {
            changes.append(SettingChange(key: "Group Name", oldValue: before.name, newValue: after.name))
        }

        if before.isEnabled != after.isEnabled {
            changes.append(
                SettingChange(
                    key: "Group Enabled",
                    oldValue: before.isEnabled ? "enabled" : "disabled",
                    newValue: after.isEnabled ? "enabled" : "disabled"
                )
            )
        }

        if before.shouldOpenAppIfNeeded != after.shouldOpenAppIfNeeded {
            changes.append(
                SettingChange(
                    key: "Cycling Mode",
                    oldValue: before.shouldOpenAppIfNeeded ? "all apps (open if needed)" : "running apps only",
                    newValue: after.shouldOpenAppIfNeeded ? "all apps (open if needed)" : "running apps only"
                )
            )
        }

        if beforeShortcut != afterShortcut {
            changes.append(
                SettingChange(
                    key: "Keyboard Shortcut",
                    oldValue: shortcutLabel(beforeShortcut),
                    newValue: shortcutLabel(afterShortcut)
                )
            )
        }

        return changes
    }

    private static func normalizedShortcutMap(_ shortcuts: [String: ShortcutData]?) -> [UUID: ShortcutData] {
        guard let shortcuts else { return [:] }
        var result: [UUID: ShortcutData] = [:]
        for (groupID, shortcut) in shortcuts {
            guard let uuid = UUID(uuidString: groupID) else { continue }
            result[uuid] = shortcut
        }
        return result
    }

    private static func shortcutLabel(_ shortcut: ShortcutData?) -> String {
        guard let shortcut else { return "none" }

        let parsed = KeyboardShortcuts.Shortcut(
            carbonKeyCode: shortcut.carbonKeyCode,
            carbonModifiers: shortcut.carbonModifiers
        )

        let modifiers = parsed.modifiers.ks_symbolicRepresentation
        if let keyLabel = keyLabel(for: parsed.key) {
            return modifiers + keyLabel
        }
        if !modifiers.isEmpty {
            return "\(modifiers)keyCode:\(shortcut.carbonKeyCode)"
        }

        return "keyCode:\(shortcut.carbonKeyCode)"
    }

    private static func keyLabel(for key: KeyboardShortcuts.Key?) -> String? {
        guard let key else { return nil }

        switch key {
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .h: return "H"
        case .i: return "I"
        case .j: return "J"
        case .k: return "K"
        case .l: return "L"
        case .m: return "M"
        case .n: return "N"
        case .o: return "O"
        case .p: return "P"
        case .q: return "Q"
        case .r: return "R"
        case .s: return "S"
        case .t: return "T"
        case .u: return "U"
        case .v: return "V"
        case .w: return "W"
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        case .zero: return "0"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .return: return "↩"
        case .tab: return "⇥"
        case .space: return "Space"
        case .delete: return "⌫"
        case .deleteForward: return "⌦"
        case .escape: return "⎋"
        case .upArrow: return "↑"
        case .rightArrow: return "→"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .f13: return "F13"
        case .f14: return "F14"
        case .f15: return "F15"
        case .f16: return "F16"
        case .f17: return "F17"
        case .f18: return "F18"
        case .f19: return "F19"
        case .f20: return "F20"
        default:
            return nil
        }
    }

    private static func computeAppChanges(before: [AppItem], after: [AppItem]) -> [AppChange] {
        let beforeMap = Dictionary(uniqueKeysWithValues: before.map { ($0.bundleIdentifier, $0) })
        let afterMap = Dictionary(uniqueKeysWithValues: after.map { ($0.bundleIdentifier, $0) })
        let beforeOrder = Dictionary(uniqueKeysWithValues: before.enumerated().map { ($1.bundleIdentifier, $0) })

        var changes: [AppChange] = []

        for (index, app) in after.enumerated() {
            if let old = beforeMap[app.bundleIdentifier] {
                let nameChanged = old.name != app.name
                let orderChanged = beforeOrder[app.bundleIdentifier] != index
                let status: DiffStatus = (nameChanged || orderChanged) ? .modified : .unchanged
                changes.append(
                    AppChange(
                        appName: app.name,
                        bundleIdentifier: app.bundleIdentifier,
                        status: status,
                        oldAppName: nameChanged ? old.name : nil
                    )
                )
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

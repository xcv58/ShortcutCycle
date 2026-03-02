import Foundation

// MARK: - URL Scheme Types

public enum URLGroupTarget: Equatable {
    case id(UUID)
    case name(String)
    case index(Int) // 1-based index for user-facing URLs
}

public enum URLSettingsTab: String, Equatable {
    case groups
    case general
}

public enum URLBackupTarget: Equatable {
    case index(Int) // 1-based index (1 = most recent backup)
    case name(String)
    case path(String)
}

public enum ShortcutCycleURLCommand: Equatable {
    case openSettings(URLSettingsTab?)
    case openBackupBrowser
    case cycle(URLGroupTarget?)
    case selectGroup(URLGroupTarget)
    case enableGroup(URLGroupTarget)
    case disableGroup(URLGroupTarget)
    case toggleGroup(URLGroupTarget)
    case backup
    case flushAutoSave
    case setSetting(key: String, value: String)
    case exportSettings(path: String?)
    case importSettings(path: String)
    case restoreBackup(URLBackupTarget?)
    case createGroup(name: String)
    case deleteGroup(URLGroupTarget)
    case renameGroup(URLGroupTarget, newName: String)
    case reorderGroup(URLGroupTarget, position: Int)
    case addApp(URLGroupTarget, bundleId: String)
    case removeApp(URLGroupTarget, bundleId: String)
    case listGroups
    case getGroup(URLGroupTarget)
}

// MARK: - URL Parser

public enum ShortcutCycleURLParser {
    public static let scheme = "shortcutcycle"
    public static let queryResultFileName = "shortcutcycle-result.json"

    private enum ParameterParseResult<T> {
        case value(T)
        case none
        case invalid
    }

    private enum OpenSettingsDestination {
        case settings(URLSettingsTab?)
        case backupBrowser
    }

    private enum BackupTargetParseResult {
        case target(URLBackupTarget?)
        case invalid
    }

    public static func parse(_ url: URL) -> ShortcutCycleURLCommand? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard let action = resolveAction(from: components) else { return nil }

        let query = queryDictionary(from: components)
        let target = parseGroupTarget(from: query)

        switch action {
        case "settings", "open-settings":
            switch parseOpenSettingsDestination(from: query) {
            case .value(.backupBrowser):
                return .openBackupBrowser
            case .value(.settings(let tab)):
                return .openSettings(tab)
            case .none:
                return .openSettings(nil)
            case .invalid:
                return nil
            }
        case "open-backup-browser", "backup-browser", "automatic-backups":
            return .openBackupBrowser
        case "cycle":
            switch target {
            case .value(let groupTarget):
                return .cycle(groupTarget)
            case .none:
                return .cycle(nil)
            case .invalid:
                return nil
            }
        case "select-group":
            guard case .value(let target) = target else { return nil }
            return .selectGroup(target)
        case "enable-group":
            guard case .value(let target) = target else { return nil }
            return .enableGroup(target)
        case "disable-group":
            guard case .value(let target) = target else { return nil }
            return .disableGroup(target)
        case "toggle-group":
            guard case .value(let target) = target else { return nil }
            return .toggleGroup(target)
        case "backup":
            return .backup
        case "flush-auto-save", "flush-auto-backup", "trigger-auto-save", "trigger-auto-backup", "autosave":
            return .flushAutoSave
        case "set-setting":
            guard let key = (query["key"] ?? query["name"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty,
                  let value = (query["value"] ?? query["v"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return nil
            }
            let normalizedKey = key.lowercased()
            let normalizedValue = value.lowercased()
            guard isSupportedSettingValue(normalizedValue, for: normalizedKey) else { return nil }
            return .setSetting(key: normalizedKey, value: normalizedValue)
        case "export-settings", "export":
            switch parsePathValue(from: query) {
            case .value(let path):
                return .exportSettings(path: path)
            case .none:
                return .exportSettings(path: nil)
            case .invalid:
                return nil
            }
        case "import-settings", "import":
            guard case .value(let path) = parsePathValue(from: query) else { return nil }
            return .importSettings(path: path)
        case "restore-backup", "restore":
            switch parseBackupTarget(from: query) {
            case .target(let target):
                return .restoreBackup(target)
            case .invalid:
                return nil
            }
        case "create-group":
            let name = (query["name"] ?? query["group"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { return nil }
            return .createGroup(name: name)
        case "delete-group":
            guard case .value(let target) = target else { return nil }
            return .deleteGroup(target)
        case "rename-group":
            guard case .value(let target) = target, let newName = parseNewName(from: query) else { return nil }
            return .renameGroup(target, newName: newName)
        case "reorder-group":
            guard case .value(let target) = target, let position = parsePosition(from: query) else { return nil }
            return .reorderGroup(target, position: position)
        case "add-app":
            guard case .value(let target) = target, let bundleId = parseBundleId(from: query) else { return nil }
            return .addApp(target, bundleId: bundleId)
        case "remove-app":
            guard case .value(let target) = target, let bundleId = parseBundleId(from: query) else { return nil }
            return .removeApp(target, bundleId: bundleId)
        case "list-groups":
            return .listGroups
        case "get-group":
            guard case .value(let target) = target else { return nil }
            return .getGroup(target)
        default:
            return nil
        }
    }

    private static func resolveAction(from components: URLComponents) -> String? {
        let host = components.host?.lowercased()
        let pathComponents = components.path
            .split(separator: "/")
            .map { $0.lowercased() }

        // Support x-callback style:
        // shortcutcycle://x-callback-url/cycle?group=Browsers
        if host == "x-callback-url" {
            return pathComponents.first
        }

        if let host, !host.isEmpty {
            return host
        }

        return pathComponents.first
    }

    private static func queryDictionary(from components: URLComponents) -> [String: String] {
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }
        return query
    }

    private static func parseGroupTarget(from query: [String: String]) -> ParameterParseResult<URLGroupTarget> {
        if let rawId = query["groupid"] ?? query["id"] {
            let idText = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !idText.isEmpty, let uuid = UUID(uuidString: idText) else { return .invalid }
            return .value(.id(uuid))
        }

        if let rawIndex = query["index"] ?? query["groupindex"] {
            let indexText = rawIndex.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let index = Int(indexText), index > 0 else { return .invalid }
            return .value(.index(index))
        }

        if let rawName = query["group"] ?? query["name"] {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .invalid }
            return .value(.name(name))
        }

        return .none
    }

    private static func parseOpenSettingsDestination(from query: [String: String]) -> ParameterParseResult<OpenSettingsDestination> {
        let routingKeys = ["tab", "section", "panel", "view"]
        for key in routingKeys {
            guard let rawValue = query[key] else { continue }
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty else { return .invalid }

            switch value {
            case "backup", "backups", "backup-browser", "automatic-backups":
                return .value(.backupBrowser)
            case "groups", "group":
                guard key == "tab" else { return .invalid }
                return .value(.settings(.groups))
            case "general", "app", "application":
                guard key == "tab" else { return .invalid }
                return .value(.settings(.general))
            default:
                return .invalid
            }
        }
        return .none
    }

    private static func parsePathValue(from query: [String: String]) -> ParameterParseResult<String> {
        let raw = query["path"] ?? query["file"]
        guard let raw else { return .none }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return .invalid }
        return .value(path)
    }

    private static func parseBackupTarget(from query: [String: String]) -> BackupTargetParseResult {
        switch parsePathValue(from: query) {
        case .value(let path):
            return .target(.path(path))
        case .invalid:
            return .invalid
        case .none:
            break
        }

        if let rawName = query["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !rawName.isEmpty else { return .invalid }
            return .target(.name(rawName))
        }

        if let rawIndex = query["index"] ?? query["backupindex"] {
            let trimmed = rawIndex.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let index = Int(trimmed), index > 0 else {
                return .invalid
            }
            return .target(.index(index))
        }

        // nil => latest backup
        return .target(nil)
    }

    private static func parseNewName(from query: [String: String]) -> String? {
        let raw = (query["newname"] ?? query["to"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    private static func parsePosition(from query: [String: String]) -> Int? {
        let raw = query["position"] ?? query["to"]
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pos = Int(trimmed), pos > 0 else { return nil }
        return pos
    }

    private static func parseBundleId(from query: [String: String]) -> String? {
        let raw = (query["bundleid"] ?? query["app"] ?? query["bundle"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    private static func isSupportedSettingValue(_ value: String, for key: String) -> Bool {
        switch key {
        case "showhud", "hud", "showshortcutinhud", "hudshortcut", "showshortcut", "openatlogin", "launchatlogin":
            return [
                "1", "true", "yes", "on", "enabled",
                "0", "false", "no", "off", "disabled"
            ].contains(value)
        case "apptheme", "theme", "appearance":
            return ["system", "default", "light", "dark"].contains(value)
        case "selectedlanguage", "language":
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

}

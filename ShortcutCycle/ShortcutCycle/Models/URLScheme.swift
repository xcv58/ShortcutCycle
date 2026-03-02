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

    public static func parse(_ url: URL) -> ShortcutCycleURLCommand? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard let action = resolveAction(from: components) else { return nil }

        let query = queryDictionary(from: components)
        let target = parseGroupTarget(from: query)

        switch action {
        case "settings", "open-settings":
            if shouldOpenBackupBrowser(from: query) {
                return .openBackupBrowser
            }
            return .openSettings(parseSettingsTab(from: query))
        case "open-backup-browser", "backup-browser", "automatic-backups":
            return .openBackupBrowser
        case "cycle":
            return .cycle(target)
        case "select-group":
            guard let target else { return nil }
            return .selectGroup(target)
        case "enable-group":
            guard let target else { return nil }
            return .enableGroup(target)
        case "disable-group":
            guard let target else { return nil }
            return .disableGroup(target)
        case "toggle-group":
            guard let target else { return nil }
            return .toggleGroup(target)
        case "backup":
            return .backup
        case "flush-auto-save", "flush-auto-backup", "trigger-auto-save", "trigger-auto-backup", "autosave":
            return .flushAutoSave
        case "set-setting":
            guard let key = (query["key"] ?? query["name"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty,
                  let value = (query["value"] ?? query["v"])?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return nil
            }
            return .setSetting(key: key.lowercased(), value: value.lowercased())
        case "export-settings", "export":
            let rawPath = query["path"] ?? query["file"]
            return .exportSettings(path: rawPath)
        case "import-settings", "import":
            guard let path = parsePathValue(from: query) else { return nil }
            return .importSettings(path: path)
        case "restore-backup", "restore":
            return .restoreBackup(parseBackupTarget(from: query))
        case "create-group":
            let name = (query["name"] ?? query["group"])?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { return nil }
            return .createGroup(name: name)
        case "delete-group":
            guard let target else { return nil }
            return .deleteGroup(target)
        case "rename-group":
            guard let target, let newName = parseNewName(from: query) else { return nil }
            return .renameGroup(target, newName: newName)
        case "reorder-group":
            guard let target, let position = parsePosition(from: query) else { return nil }
            return .reorderGroup(target, position: position)
        case "add-app":
            guard let target, let bundleId = parseBundleId(from: query) else { return nil }
            return .addApp(target, bundleId: bundleId)
        case "remove-app":
            guard let target, let bundleId = parseBundleId(from: query) else { return nil }
            return .removeApp(target, bundleId: bundleId)
        case "list-groups":
            return .listGroups
        case "get-group":
            guard let target else { return nil }
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
            guard let value = item.value else { continue }
            query[item.name.lowercased()] = value
        }
        return query
    }

    private static func parseGroupTarget(from query: [String: String]) -> URLGroupTarget? {
        if let idText = query["groupid"] ?? query["id"],
           let uuid = UUID(uuidString: idText) {
            return .id(uuid)
        }

        if let indexText = query["index"] ?? query["groupindex"],
           let index = Int(indexText), index > 0 {
            return .index(index)
        }

        if let rawName = query["group"] ?? query["name"] {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return .name(name)
            }
        }

        return nil
    }

    private static func parseSettingsTab(from query: [String: String]) -> URLSettingsTab? {
        guard let rawTab = query["tab"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawTab.isEmpty else {
            return nil
        }

        switch rawTab {
        case "groups", "group":
            return .groups
        case "general", "app", "application":
            return .general
        default:
            return nil
        }
    }

    private static func shouldOpenBackupBrowser(from query: [String: String]) -> Bool {
        let candidates = [
            query["tab"],
            query["section"],
            query["panel"],
            query["view"]
        ]
        let value = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first(where: { !$0.isEmpty })

        guard let value else { return false }
        return value == "backup" ||
               value == "backups" ||
               value == "backup-browser" ||
               value == "automatic-backups"
    }

    private static func parsePathValue(from query: [String: String]) -> String? {
        let raw = query["path"] ?? query["file"]
        guard let raw else { return nil }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func parseBackupTarget(from query: [String: String]) -> URLBackupTarget? {
        if let path = parsePathValue(from: query) {
            return .path(path)
        }

        if let rawName = query["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawName.isEmpty {
            return .name(rawName)
        }

        if let rawIndex = query["index"] ?? query["backupindex"],
           let index = Int(rawIndex), index > 0 {
            return .index(index)
        }

        // nil => latest backup
        return nil
    }

    private static func parseNewName(from query: [String: String]) -> String? {
        let raw = (query["newname"] ?? query["to"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    private static func parsePosition(from query: [String: String]) -> Int? {
        let raw = query["position"] ?? query["to"]
        guard let raw, let pos = Int(raw), pos > 0 else { return nil }
        return pos
    }

    private static func parseBundleId(from query: [String: String]) -> String? {
        let raw = (query["bundleid"] ?? query["app"] ?? query["bundle"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

}

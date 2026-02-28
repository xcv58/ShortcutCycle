import Foundation
import KeyboardShortcuts

/// Data for a single keyboard shortcut
public struct ShortcutData: Codable, Equatable {
    public let carbonKeyCode: Int
    public let carbonModifiers: Int

    public init(carbonKeyCode: Int, carbonModifiers: Int) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
    }
}

/// App preferences stored in @AppStorage
public struct AppSettings: Codable, Equatable {
    public var showHUD: Bool
    public var showShortcutInHUD: Bool
    public var selectedLanguage: String?
    public var appTheme: String?
    public var perWindowMode: Bool?

    public init(showHUD: Bool, showShortcutInHUD: Bool, selectedLanguage: String? = nil, appTheme: String? = nil, perWindowMode: Bool? = nil) {
        self.showHUD = showHUD
        self.showShortcutInHUD = showShortcutInHUD
        self.selectedLanguage = selectedLanguage
        self.appTheme = appTheme
        self.perWindowMode = perWindowMode
    }

    /// Load current settings from UserDefaults
    public static func current() -> AppSettings {
        AppSettings(
            showHUD: UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true,
            showShortcutInHUD: UserDefaults.standard.object(forKey: "showShortcutInHUD") as? Bool ?? true,
            selectedLanguage: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system",
            appTheme: UserDefaults.standard.string(forKey: "appTheme") ?? "system",
            perWindowMode: UserDefaults.standard.object(forKey: "perWindowMode") as? Bool
        )
    }

    /// Apply settings to UserDefaults
    public func apply() {
        UserDefaults.standard.set(showHUD, forKey: "showHUD")
        UserDefaults.standard.set(showShortcutInHUD, forKey: "showShortcutInHUD")
        UserDefaults.standard.set(selectedLanguage ?? "system", forKey: "selectedLanguage")
        if let appTheme = appTheme {
            UserDefaults.standard.set(appTheme, forKey: "appTheme")
        }
        if let perWindowMode = perWindowMode {
            UserDefaults.standard.set(perWindowMode, forKey: "perWindowMode")
        }
    }
}

/// Wrapper for settings export with version for future compatibility
public struct SettingsExport: Codable {
    public let version: Int
    public let exportDate: Date
    public let groups: [AppGroup]
    public let settings: AppSettings?
    public let shortcuts: [String: ShortcutData]?

    /// Current export format version
    public static let currentVersion = 3

    public init(groups: [AppGroup], settings: AppSettings? = nil, shortcuts: [String: ShortcutData]? = nil) {
        self.version = Self.currentVersion
        self.exportDate = Date()
        self.groups = groups
        self.settings = settings
        self.shortcuts = shortcuts
    }

    /// Create a full export snapshot including keyboard shortcuts
    @MainActor
    public static func fullSnapshot(groups: [AppGroup]) -> SettingsExport {
        var shortcutMap: [String: ShortcutData] = [:]
        for group in groups {
            if let shortcut = KeyboardShortcuts.getShortcut(for: group.shortcutName) {
                shortcutMap[group.id.uuidString] = ShortcutData(
                    carbonKeyCode: shortcut.carbonKeyCode,
                    carbonModifiers: shortcut.carbonModifiers
                )
            }
        }
        return SettingsExport(
            groups: groups,
            settings: AppSettings.current(),
            shortcuts: shortcutMap.isEmpty ? nil : shortcutMap
        )
    }

    /// Apply imported shortcuts to KeyboardShortcuts
    @MainActor
    public func applyShortcuts() {
        guard let shortcuts = shortcuts else { return }
        for group in groups {
            let key = group.id.uuidString
            if let data = shortcuts[key] {
                let shortcut = KeyboardShortcuts.Shortcut(
                    carbonKeyCode: data.carbonKeyCode,
                    carbonModifiers: data.carbonModifiers
                )
                KeyboardShortcuts.setShortcut(shortcut, for: group.shortcutName)
            }
        }
    }

    /// Validate that this export has the expected structure
    public static func validate(data: Data) -> Result<SettingsExport, SettingsExportError> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let export = try decoder.decode(SettingsExport.self, from: data)
            guard export.version > 0 else {
                return .failure(.invalidVersion)
            }
            return .success(export)
        } catch {
            return .failure(.invalidFormat(error.localizedDescription))
        }
    }

}

public enum SettingsExportError: LocalizedError {
    case invalidFormat(String)
    case invalidVersion
    case emptyData

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let detail):
            return "Invalid settings format: \(detail)"
        case .invalidVersion:
            return "Invalid settings version"
        case .emptyData:
            return "No data to import"
        }
    }
}

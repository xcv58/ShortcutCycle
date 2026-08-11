import Foundation
import KeyboardShortcuts

enum AppleLanguagePreferenceSync {
    // Keep in sync with LanguageManager.supportedLanguages. LocalizationTests
    // verifies this list and the app's other localization sources stay aligned.
    static let supportedLanguageCodes = [
        "en", "de", "fr", "es", "ja", "pt-BR", "zh-Hans", "zh-Hant",
        "it", "ko", "ar", "nl", "pl", "tr", "ru"
    ]

    static func resolvedPreferredLanguages(
        from globalPreferenceValue: CFPropertyList?,
        fallback: [String] = Locale.preferredLanguages
    ) -> [String] {
        if let languages = globalPreferenceValue as? [String] {
            return languages
        }

        return fallback
    }

    private static var globalPreferredLanguages: [String] {
        resolvedPreferredLanguages(
            from: CFPreferencesCopyValue(
                "AppleLanguages" as CFString,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ),
            fallback: Locale.preferredLanguages
        )
    }

    static func sync(_ selectedLanguage: String, userDefaults: UserDefaults = .standard) {
        let preferredLocalization = Bundle.preferredLocalizations(
            from: supportedLanguageCodes,
            forPreferences: globalPreferredLanguages
        ).first
        let effectiveCode = effectiveLanguageCode(
            selectedLanguage: selectedLanguage,
            preferredLocalization: preferredLocalization
        )
        let appleCode = appleLanguageCode(for: effectiveCode)
        userDefaults.set([appleCode], forKey: "AppleLanguages")
    }

    static func effectiveLanguageCode(selectedLanguage: String, preferredLocalization: String?) -> String {
        if selectedLanguage == "system" {
            return preferredLocalization ?? "en"
        }
        return selectedLanguage
    }

    static func appleLanguageCode(for effectiveCode: String) -> String {
        effectiveCode == "zh-Hant" ? "zh-TW" : effectiveCode
    }
}

/// Data for a single keyboard shortcut
public struct ShortcutData: Codable, Equatable {
    public let carbonKeyCode: Int
    public let carbonModifiers: Int

    public init(carbonKeyCode: Int, carbonModifiers: Int) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
    }

    public init(_ shortcut: KeyboardShortcuts.Shortcut) {
        self.init(
            carbonKeyCode: shortcut.carbonKeyCode,
            carbonModifiers: shortcut.carbonModifiers
        )
    }

    public var shortcut: KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(
            carbonKeyCode: carbonKeyCode,
            carbonModifiers: carbonModifiers
        )
    }
}

/// App preferences stored in @AppStorage
public struct AppSettings: Codable, Equatable {
    public var showHUD: Bool
    public var showShortcutInHUD: Bool
    public var selectedLanguage: String?
    public var appTheme: String?

    public init(showHUD: Bool, showShortcutInHUD: Bool, selectedLanguage: String? = nil, appTheme: String? = nil) {
        self.showHUD = showHUD
        self.showShortcutInHUD = showShortcutInHUD
        self.selectedLanguage = selectedLanguage
        self.appTheme = appTheme
    }

    /// Load current settings from UserDefaults
    public static func current(userDefaults: UserDefaults = .standard) -> AppSettings {
        AppSettings(
            showHUD: userDefaults.object(forKey: "showHUD") as? Bool ?? true,
            showShortcutInHUD: userDefaults.object(forKey: "showShortcutInHUD") as? Bool ?? true,
            selectedLanguage: userDefaults.string(forKey: "selectedLanguage") ?? "system",
            appTheme: userDefaults.string(forKey: "appTheme") ?? "system"
        )
    }

    /// Apply settings to UserDefaults
    public func apply() {
        UserDefaults.standard.set(showHUD, forKey: "showHUD")
        UserDefaults.standard.set(showShortcutInHUD, forKey: "showShortcutInHUD")
        let resolvedLanguage = selectedLanguage ?? "system"
        UserDefaults.standard.set(resolvedLanguage, forKey: "selectedLanguage")
        AppleLanguagePreferenceSync.sync(resolvedLanguage)
        if let appTheme = appTheme {
            UserDefaults.standard.set(appTheme, forKey: "appTheme")
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

    /// Validate every imported shortcut before replacing the persisted set.
    ///
    /// Duplicate shortcuts in the payload are rejected here. Runtime-specific
    /// reservations (for example, app menu commands and macOS hotkeys) are
    /// supplied by the app target through `validator`.
    @MainActor
    func applyShortcuts(
        validatingWith validator: (
            KeyboardShortcuts.Shortcut,
            ShortcutAssignmentOwner
        ) -> ShortcutAssignmentRejection?
    ) -> ShortcutAssignmentRejection? {
        var assignments: [(group: AppGroup, shortcut: KeyboardShortcuts.Shortcut)] = []

        for group in groups {
            for recentShortcut in group.recentShortcuts ?? [] {
                if let rejection = ShortcutAssignmentEligibility.rawDataRejection(
                    for: recentShortcut
                ) {
                    return rejection
                }
            }

            let key = group.id.uuidString
            if let data = shortcuts?[key] {
                if let rejection = ShortcutAssignmentEligibility.rejection(for: data) {
                    return rejection
                }

                let shortcut = data.shortcut
                let owner = ShortcutAssignmentOwner.group(id: group.id, name: group.name)

                if let duplicate = assignments.first(where: { $0.shortcut == shortcut }) {
                    return .conflict(
                        ShortcutAssignmentConflict(
                            shortcut: shortcut,
                            owner: .group(id: duplicate.group.id, name: duplicate.group.name)
                        )
                    )
                }

                if let conflict = validator(shortcut, owner) {
                    return conflict
                }

                assignments.append((group, shortcut))
            }
        }

        // The import is a replacement snapshot. Reset every persisted shortcut
        // name so historical group assignments are removed, while preserving
        // the Settings-window shortcut which is not part of the export format.
        let settingsShortcut = KeyboardShortcuts.getShortcut(for: .toggleSettings)
        KeyboardShortcuts.resetAll()
        KeyboardShortcuts.setShortcut(settingsShortcut, for: .toggleSettings)

        for assignment in assignments {
            KeyboardShortcuts.setShortcut(
                assignment.shortcut,
                for: assignment.group.shortcutName
            )
        }

        return nil
    }

    /// Validate that this export has the expected structure
    public static func validate(data: Data) -> Result<SettingsExport, SettingsExportError> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let export = try decoder.decode(SettingsExport.self, from: data)
            guard (1...currentVersion).contains(export.version) else {
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

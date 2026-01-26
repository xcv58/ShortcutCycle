import Foundation

/// App preferences stored in @AppStorage
struct AppSettings: Codable {
    var showHUD: Bool
    var showShortcutInHUD: Bool
    var selectedLanguage: String // "system" (default) or language code e.g. "en", "fr"
    
    /// Load current settings from UserDefaults
    static func current() -> AppSettings {
        AppSettings(
            showHUD: UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true,
            showShortcutInHUD: UserDefaults.standard.object(forKey: "showShortcutInHUD") as? Bool ?? true,
            selectedLanguage: UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system"
        )
    }
    
    /// Apply settings to UserDefaults
    func apply() {
        UserDefaults.standard.set(showHUD, forKey: "showHUD")
        UserDefaults.standard.set(showShortcutInHUD, forKey: "showShortcutInHUD")
        UserDefaults.standard.set(selectedLanguage, forKey: "selectedLanguage")
    }
}

/// Wrapper for settings export with version for future compatibility
struct SettingsExport: Codable {
    let version: Int
    let exportDate: Date
    let groups: [AppGroup]
    let settings: AppSettings?
    
    /// Current export format version
    static let currentVersion = 2
    
    init(groups: [AppGroup], settings: AppSettings? = nil) {
        self.version = Self.currentVersion
        self.exportDate = Date()
        self.groups = groups
        self.settings = settings
    }
}

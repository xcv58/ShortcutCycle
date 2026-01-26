import Foundation

/// App preferences stored in @AppStorage
struct AppSettings: Codable {
    var showHUD: Bool
    var showShortcutInHUD: Bool
    
    /// Load current settings from UserDefaults
    static func current() -> AppSettings {
        AppSettings(
            showHUD: UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true,
            showShortcutInHUD: UserDefaults.standard.object(forKey: "showShortcutInHUD") as? Bool ?? true
        )
    }
    
    /// Apply settings to UserDefaults
    func apply() {
        UserDefaults.standard.set(showHUD, forKey: "showHUD")
        UserDefaults.standard.set(showShortcutInHUD, forKey: "showShortcutInHUD")
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

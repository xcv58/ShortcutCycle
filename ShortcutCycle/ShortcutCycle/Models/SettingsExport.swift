import Foundation

/// Wrapper for settings export with version for future compatibility
struct SettingsExport: Codable {
    let version: Int
    let exportDate: Date
    let groups: [AppGroup]
    
    /// Current export format version
    static let currentVersion = 1
    
    init(groups: [AppGroup]) {
        self.version = Self.currentVersion
        self.exportDate = Date()
        self.groups = groups
    }
}

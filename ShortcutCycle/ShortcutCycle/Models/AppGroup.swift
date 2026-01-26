import Foundation
import KeyboardShortcuts

/// Represents a group of applications with a shared keyboard shortcut
struct AppGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var apps: [AppItem]
    var lastActiveAppBundleId: String?
    var isEnabled: Bool = true
    var lastModified: Date = Date()
    
    // Legacy property for migration - will be ignored after first load
    // This allows old data to be decoded without crashing
    private var shortcut: LegacyKeyboardShortcutData?
    
    init(id: UUID = UUID(), name: String, apps: [AppItem] = [], isEnabled: Bool = true, lastModified: Date = Date()) {
        self.id = id
        self.name = name
        self.apps = apps
        self.isEnabled = isEnabled
        self.lastModified = lastModified
    }
    
    mutating func addApp(_ app: AppItem) {
        if !apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            apps.append(app)
            lastModified = Date()
        }
    }
    
    mutating func removeApp(_ app: AppItem) {
        apps.removeAll { $0.id == app.id }
        lastModified = Date()
    }
    
    mutating func moveApp(from source: IndexSet, to destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
        lastModified = Date()
    }
    
    /// Get the KeyboardShortcuts.Name for this group
    var shortcutName: KeyboardShortcuts.Name {
        .forGroup(id)
    }
}

/// Legacy struct for backward compatibility during migration
/// This allows the app to read old data without crashing
private struct LegacyKeyboardShortcutData: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

// MARK: - MainActor helper for shortcut access
extension AppGroup {
    /// Check if this group has a shortcut assigned (must be called from main actor)
    @MainActor
    var hasShortcut: Bool {
        KeyboardShortcuts.getShortcut(for: shortcutName) != nil
    }
    
    /// Get the display string for the current shortcut (if any) - must be called from main actor
    @MainActor
    var shortcutDisplayString: String? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: shortcutName) else {
            return nil
        }
        return shortcut.description
    }
}

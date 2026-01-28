import Foundation
import KeyboardShortcuts

/// Represents a group of applications with a shared keyboard shortcut
public struct AppGroup: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var apps: [AppItem]
    public var lastActiveAppBundleId: String?
    public var isEnabled: Bool = true
    public var lastModified: Date = Date()
    public var openAppIfNeeded: Bool?
    
    public var shouldOpenAppIfNeeded: Bool {
        openAppIfNeeded ?? false
    }
    
    // Legacy property for migration - will be ignored after first load
    // This allows old data to be decoded without crashing
    private var shortcut: LegacyKeyboardShortcutData?
    
    public init(id: UUID = UUID(), name: String, apps: [AppItem] = [], isEnabled: Bool = true, openAppIfNeeded: Bool? = nil, lastModified: Date = Date()) {
        self.id = id
        self.name = name
        self.apps = apps
        self.isEnabled = isEnabled
        self.openAppIfNeeded = openAppIfNeeded
        self.lastModified = lastModified
    }
    
    public mutating func addApp(_ app: AppItem) {
        if !apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            apps.append(app)
            lastModified = Date()
        }
    }
    
    public mutating func removeApp(_ app: AppItem) {
        apps.removeAll { $0.id == app.id }
        lastModified = Date()
    }
    
    public mutating func moveApp(from source: IndexSet, to destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
        lastModified = Date()
    }
    
    /// Get the KeyboardShortcuts.Name for this group
    public var shortcutName: KeyboardShortcuts.Name {
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
public extension AppGroup {
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

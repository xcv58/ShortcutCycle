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

// MARK: - Notification Names
public extension Notification.Name {
    /// Posted when groups or shortcuts have changed and need re-registration
    static let shortcutsNeedUpdate = Notification.Name("ShortcutsNeedUpdate")
}

// MARK: - App Cycling Logic

/// Represents an item that can be cycled through
public struct CyclingAppItem: Identifiable, Equatable {
    public let id: String
    
    public init(id: String) {
        self.id = id
    }
}

public enum AppCyclingLogic {
    /// Determines the next app ID to switch to
    /// - Parameters:
    ///   - items: List of available apps to cycle through
    ///   - currentFrontmostAppId: The bundle ID of the currently frontmost app
    ///   - currentHUDSelectionId: The bundle ID currently selected in the HUD (if visible)
    ///   - lastActiveAppId: The bundle ID of the last active app in this group
    ///   - isHUDVisible: Whether the HUD is currently visible
    /// - Returns: The bundle ID of the next app to activate
    public static func nextAppId(
        items: [CyclingAppItem],
        currentFrontmostAppId: String?,
        currentHUDSelectionId: String?,
        lastActiveAppId: String?,
        isHUDVisible: Bool
    ) -> String {
        guard !items.isEmpty else {
            // Fallback if no items (should not happen in caller, but safe)
            return "" 
        }
        
        // 1. If HUD is already visible, we are interacting with the list.
        // Cycle from the currently selected item in the HUD.
        if isHUDVisible, let currentID = currentHUDSelectionId {
            if let currentIndex = items.firstIndex(where: { $0.id == currentID }) {
                let nextIndex = (currentIndex + 1) % items.count
                return items[nextIndex].id
            } else {
                // Current selection not in items (e.g. closed?), restart from 0
                return items[0].id
            }
        }
        
        // 2. HUD is NOT visible. This is a new cycle start.
        
        // Check if the frontmost app is part of our group
        if let frontmostID = currentFrontmostAppId,
           let currentIndex = items.firstIndex(where: { $0.id == frontmostID }) {
            // We are gathering "speed" from the current app. Go to next.
            let nextIndex = (currentIndex + 1) % items.count
            return items[nextIndex].id
        }
        
        // 3. Frontmost app is NOT in the group (or we are not in it).
        // Use the last active app for this group if available.
        if let lastID = lastActiveAppId,
           items.contains(where: { $0.id == lastID }) {
            return lastID
        }
        
        // 4. Default to first item
        return items[0].id
    }
}

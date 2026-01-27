import Foundation
import KeyboardShortcuts
import AppKit

/// Manages global keyboard shortcuts using the KeyboardShortcuts library
@MainActor
class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()
    
    private var groupStore: GroupStore?
    
    private var registeredGroupIds: Set<UUID> = []
    
    private init() {}
    
    func setGroupStore(_ store: GroupStore) {
        self.groupStore = store
    }
    
    /// Register all shortcuts from the group store
    func registerAllShortcuts() {
        // Register the settings toggle shortcut
        KeyboardShortcuts.onKeyUp(for: .toggleSettings) { [weak self] in
            Task { @MainActor in
                self?.handleToggleSettings()
            }
        }
        
        // Unregister all previously registered shortcuts first
        // This is crucial to handle deleted groups or disabled groups
        unregisterAllShortcuts()
        
        guard let store = groupStore else { return }
        
        // Register shortcuts for each enabled group that has a shortcut
        for group in store.groups where group.isEnabled {
            registerShortcut(for: group)
        }
    }
    
    /// Register a single shortcut handler for a group
    func registerShortcut(for group: AppGroup) {
        let shortcutName = group.shortcutName
        
        // Only register if group has a shortcut assigned
        guard KeyboardShortcuts.getShortcut(for: shortcutName) != nil else {
            return
        }
        
        let groupId = group.id
        
        // Register the callback for when the shortcut is pressed
        KeyboardShortcuts.onKeyUp(for: shortcutName) { [weak self] in
            Task { @MainActor in
                self?.handleShortcut(for: groupId)
            }
        }
        
        registeredGroupIds.insert(groupId)

    }
    
    /// Unregister a shortcut for a specific group
    func unregisterShortcut(for groupId: UUID) {
        let shortcutName = KeyboardShortcuts.Name.forGroup(groupId)
        KeyboardShortcuts.disable(shortcutName)
        registeredGroupIds.remove(groupId)
    }
    
    /// Unregister all shortcuts
    private func unregisterAllShortcuts() {
        for groupId in registeredGroupIds {
            let shortcutName = KeyboardShortcuts.Name.forGroup(groupId)
            KeyboardShortcuts.disable(shortcutName)
        }
        registeredGroupIds.removeAll()
    }
    
    /// Handle a shortcut press for a given group ID
    private func handleShortcut(for groupId: UUID) {
        guard let store = groupStore,
              let group = store.groups.first(where: { $0.id == groupId }) else {
            return
        }
        
        AppSwitcher.shared.handleShortcut(for: group, store: store)
    }
    
    /// Handle the settings toggle shortcut
    private func handleToggleSettings() {
        // Find if the settings window is already open
        let settingsWindow = NSApp.windows.first { window in
            // Check by identifier first (if exposed) or title
            // Note: SwiftUI windows might not expose identifier easily in NSWindow, 
            // but usually the title matches the WindowGroup title
            return window.title == "Shortcut Cycle" && window.styleMask.contains(.titled)
        }
        
        if let window = settingsWindow {
            if window.isKeyWindow {
                // If it's already the key window, close it to toggle off
                window.close()
            } else {
                // If it's open but not key, bring it to front
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            // Window is closed/not in memory.
            // There is no easy way to "open" a SwiftUI WindowGroup from here 
            // without an environment handle to openWindow.
            // However, we can use the URL scheme if we had one, or rely on NSApp.
            // A workaround for SwiftUI lifecycle apps is hard.
            // Let's try to activate the app, which might bring the default window (Settings) up if it's the only one.
            NSApp.activate(ignoringOtherApps: true)
            
            // If the app is activation policy accessory, activating it might not show a window if it was closed.
            // We might need to rely on the user keeping it open or minimize behavior.
            // Alternatively, in `ShortcutCycleApp`, we have the Window.
            // NOTE: A common workaround is to use `NSApp.sendAction`.
            // But strict SwiftUI lifecycle makes this hard.
            
            // Let's just try activating for now. If it doesn't work, we might need a more complex solution
            // involving passing a closure or notification to the App struct.
            
            // Send a notification that the App struct can listen to?
            // Or simpler: NotificationCenter
            NotificationCenter.default.post(name: Notification.Name("ToggleSettingsWindow"), object: nil)
        }
    }
    
    /// Reset a shortcut (clear the assigned key combination)
    func resetShortcut(for groupId: UUID) {
        let shortcutName = KeyboardShortcuts.Name.forGroup(groupId)
        KeyboardShortcuts.reset(shortcutName)
    }
}

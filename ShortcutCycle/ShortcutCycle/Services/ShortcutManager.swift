import Foundation
import KeyboardShortcuts
import AppKit
import Combine
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

/// Manages global keyboard shortcuts using the KeyboardShortcuts library
@MainActor
class ShortcutManager: @preconcurrency ObservableObject {
    static let shared = ShortcutManager()
    
    // Explicitly satisfy ObservableObject requirements since automatic synthesis failed
    let objectWillChange = ObservableObjectPublisher()
    
    
    private var groupStore: GroupStore {
        GroupStore.shared
    }
    
    private var registeredGroupIds: Set<UUID> = []
    private var observedGroupIds: Set<UUID> = []
    private var hasRegisteredToggleSettingsShortcut = false
    
    private init() {
        // Observers
        NotificationCenter.default.addObserver(forName: .shortcutsNeedUpdate, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.registerAllShortcuts()
            }
        }
    }
    
    /// Register all shortcuts from the group store
    func registerAllShortcuts() {
#if DEBUG
        // Register the settings toggle shortcut once.
        // KeyboardShortcuts.onKeyDown appends handlers and does not replace existing ones.
        if !hasRegisteredToggleSettingsShortcut {
            KeyboardShortcuts.onKeyDown(for: .toggleSettings) { [weak self] in
                Task { @MainActor in
                    self?.handleToggleSettings()
                }
            }
            hasRegisteredToggleSettingsShortcut = true
        }
#endif
        
        // Unregister all previously registered shortcuts first
        // This is crucial to handle deleted groups or disabled groups
        unregisterAllShortcuts()
        
        let store = groupStore
        
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
        
        // Smart Registration: Only add the listener closure ONCE per group ID
        if !observedGroupIds.contains(groupId) {
            // Register the callback for when the shortcut is pressed
            KeyboardShortcuts.onKeyDown(for: shortcutName) { [weak self] in
                Task { @MainActor in
                    self?.handleShortcut(for: groupId)
                }
            }
            observedGroupIds.insert(groupId)
        }
        
        // Always enable the shortcut (it might have been disabled by unregisterAllShortcuts)
        KeyboardShortcuts.enable(shortcutName)
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
    private var lastShortcutTime: Date?

    private func handleShortcut(for groupId: UUID) {
        // Throttle: process the first event immediately, block duplicates within 50ms.
        // This prevents double-triggers (especially with multi-modifier shortcuts) while
        // keeping cycling responsive (no delay on the first event).
        let now = Date()
        if let last = lastShortcutTime, now.timeIntervalSince(last) < 0.05 {
            return
        }
        lastShortcutTime = now

        let store = groupStore
        guard let group = store.groups.first(where: { $0.id == groupId }) else {
            return
        }

        AppSwitcher.shared.handleShortcut(for: group, store: store)
    }
    
    /// Handle the settings toggle shortcut
    private func handleToggleSettings() {
        // Find if the settings window is already open
        let settingsWindow = NSApp.windows.first { window in
            return window.identifier?.rawValue == "settings"
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
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: Notification.Name("ToggleSettingsWindow"), object: nil)
        }
    }
    
    /// Reset a shortcut (clear the assigned key combination)
    func resetShortcut(for groupId: UUID) {
        let shortcutName = KeyboardShortcuts.Name.forGroup(groupId)
        KeyboardShortcuts.reset(shortcutName)
    }
}

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
        print("Registered shortcut for group: \(group.name) (\(groupId))")
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
    
    /// Reset a shortcut (clear the assigned key combination)
    func resetShortcut(for groupId: UUID) {
        let shortcutName = KeyboardShortcuts.Name.forGroup(groupId)
        KeyboardShortcuts.reset(shortcutName)
    }
}

import Foundation
import Carbon.HIToolbox
import AppKit

/// Manages global keyboard shortcuts using Carbon Event Manager
@MainActor
class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()
    
    private var hotKeyRefs: [UUID: EventHotKeyRef] = [:]
    private var groupStore: GroupStore?
    private static var nextHotKeyId: UInt32 = 1
    private static var groupIdMap: [UInt32: UUID] = [:]
    
    private init() {
        setupEventHandler()
    }
    
    func setGroupStore(_ store: GroupStore) {
        self.groupStore = store
    }
    
    /// Register all shortcuts from the group store
    func registerAllShortcuts() {
        guard let store = groupStore else { return }
        
        // Unregister all existing shortcuts first
        unregisterAllShortcuts()
        
        // Register shortcuts for each group
        for group in store.groups {
            if let shortcut = group.shortcut {
                registerShortcut(shortcut, for: group.id)
            }
        }
    }
    
    /// Register a single shortcut for a group
    func registerShortcut(_ shortcut: KeyboardShortcutData, for groupId: UUID) {
        // Unregister existing shortcut for this group if any
        unregisterShortcut(for: groupId)
        
        var hotKeyRef: EventHotKeyRef?
        let hotKeyId = Self.nextHotKeyId
        Self.nextHotKeyId += 1
        Self.groupIdMap[hotKeyId] = groupId
        
        var hotKeyID = EventHotKeyID(signature: OSType(0x4153_4857), id: hotKeyId) // "ASHW"
        
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs[groupId] = ref
            print("Registered hotkey for group: \(groupId)")
        } else {
            print("Failed to register hotkey: \(status)")
        }
    }
    
    /// Unregister a shortcut for a group
    func unregisterShortcut(for groupId: UUID) {
        if let ref = hotKeyRefs[groupId] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: groupId)
            // Remove from groupIdMap
            Self.groupIdMap = Self.groupIdMap.filter { $0.value != groupId }
        }
    }
    
    /// Unregister all shortcuts
    private func unregisterAllShortcuts() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        Self.groupIdMap.removeAll()
    }
    
    /// Setup the Carbon event handler for hot keys
    private func setupEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                if status == noErr {
                    // Handle the hot key on the main thread
                    Task { @MainActor in
                        ShortcutManager.shared.handleHotKey(id: hotKeyID.id)
                    }
                }
                
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
    
    /// Handle a hot key press
    private func handleHotKey(id: UInt32) {
        guard let groupId = Self.groupIdMap[id],
              let store = groupStore,
              let group = store.groups.first(where: { $0.id == groupId }) else {
            return
        }
        
        AppSwitcher.shared.handleShortcut(for: group, store: store)
    }
    
    /// Convert NSEvent modifier flags to Carbon modifiers
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        
        return carbonFlags
    }
}

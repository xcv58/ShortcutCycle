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
    private var pressedGroupIds: Set<UUID> = []
    private var hasRegisteredToggleSettingsShortcut = false
    private var shortcutRecordingSuspensionCount = 0
    private var shortcutsWereEnabledBeforeRecording = true
    
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
        
        // Unregister all previously registered shortcuts first
        // This is crucial to handle deleted groups or disabled groups
        unregisterAllShortcuts()
        
        let store = groupStore
        
        // Register shortcuts for each enabled group that has a shortcut
        for group in store.groups where group.isEnabled {
            registerShortcut(for: group)
        }
    }

    /// Temporarily prevents every ShortcutCycle global shortcut from firing while
    /// a recorder owns keyboard input. The saved shortcuts remain registered so a
    /// recording can update them without creating a gap when the session ends.
    func suspendForShortcutRecording() {
        shortcutRecordingSuspensionCount += 1
        guard shortcutRecordingSuspensionCount == 1 else {
            return
        }

        shortcutsWereEnabledBeforeRecording = KeyboardShortcuts.isEnabled
        KeyboardShortcuts.isEnabled = false
    }

    /// Restores the global shortcut state after every active recorder has ended.
    func resumeAfterShortcutRecording() {
        guard shortcutRecordingSuspensionCount > 0 else {
            return
        }

        shortcutRecordingSuspensionCount -= 1
        guard shortcutRecordingSuspensionCount == 0 else {
            return
        }

        let shouldEnableShortcuts = shortcutsWereEnabledBeforeRecording
        KeyboardShortcuts.isEnabled = shouldEnableShortcuts
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
                // Carbon delivers this event on the main event loop. Capture the
                // foreground app before scheduling any HUD or activation work: a
                // later lookup can see ShortcutCycle itself instead of the app
                // from which the user invoked the shortcut.
                MainActor.assumeIsolated {
                    let frontmostAppId = Self.currentFrontmostApplicationId()
                    self?.handleShortcut(for: groupId, frontmostAppId: frontmostAppId)
                }
            }
            KeyboardShortcuts.onKeyUp(for: shortcutName) { [weak self] in
                MainActor.assumeIsolated {
                    self?.handleShortcutRelease(for: groupId)
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
        pressedGroupIds.remove(groupId)
    }
    
    /// Unregister all shortcuts
    private func unregisterAllShortcuts() {
        for groupId in registeredGroupIds {
            let shortcutName = KeyboardShortcuts.Name.forGroup(groupId)
            KeyboardShortcuts.disable(shortcutName)
        }
        registeredGroupIds.removeAll()
        pressedGroupIds.removeAll()
    }
    
    private static func currentFrontmostApplicationId() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else {
            return nil
        }
        return "\(bundleId)::\(app.processIdentifier)"
    }

    private func handleShortcut(for groupId: UUID, frontmostAppId: String?) {
        // A shortcut can emit repeated key-down events while its main key is held.
        // Treat a new physical press (one that followed key-up) as distinct, however
        // quickly it occurs, so modifier-held cycling remains responsive.
        guard !pressedGroupIds.contains(groupId) else {
            return
        }
        pressedGroupIds.insert(groupId)

        let store = groupStore
        guard let group = store.groups.first(where: { $0.id == groupId }) else {
            return
        }

        AppSwitcher.shared.handleShortcut(
            for: group,
            store: store,
            frontmostAppIdAtKeyDown: frontmostAppId
        )
    }

    private func handleShortcutRelease(for groupId: UUID) {
        pressedGroupIds.remove(groupId)
        AppSwitcher.shared.handleShortcutRelease(for: groupId)
    }
    
    /// Handle the settings toggle shortcut
    private func handleToggleSettings() {
        let settingsWindow = NSApp.windows.first { window in
            SettingsWindowLifecycleCoordinator.isSettingsWindow(window)
        }

        switch SettingsWindowLifecycleCoordinator.toggleAction(for: settingsWindow) {
        case .dismiss:
            settingsWindow?.close()
        case .focus, .open:
            ShortcutCycleURLRouter.openSettingsFromOutsideView()
        }
    }
    
    /// Reset a shortcut (clear the assigned key combination)
    func resetShortcut(for groupId: UUID) {
        let shortcutName = KeyboardShortcuts.Name.forGroup(groupId)
        KeyboardShortcuts.reset(shortcutName)
    }
}


import Foundation
import AppKit
import SwiftUI
import Carbon // For kVK constants if needed
import CoreGraphics // For CGEventSource
import KeyboardShortcuts
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

// MARK: - AppSwitcher

/// Handles the core app switching logic for groups
@MainActor
class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()
    
    private init() {
        UserDefaults.standard.register(defaults: ["showHUD": true, "showShortcutInHUD": true])
    }
    
    /// Handle a shortcut activation for a given group
    func handleShortcut(for group: AppGroup, store: GroupStore) {
        let modifierFlags = getModifierFlags(for: group)
        let shortcutString = group.shortcutDisplayString
        let activeKey = getShortcutKey(for: group)
        
        let hudItems = getHUDItems(for: group)

        // If "Open App If Needed" is enabled, we cycle through ALL apps
        if group.shouldOpenAppIfNeeded {
             if hudItems.isEmpty { return }
             cycleAllApps(hudItems: hudItems, group: group, store: store, modifierFlags: modifierFlags, shortcut: shortcutString, activeKey: activeKey)
        } else {
             // Legacy behavior: Only cycle running apps
             cycleRunningAppsOnly(hudItems: hudItems, group: group, store: store, modifierFlags: modifierFlags, shortcut: shortcutString, activeKey: activeKey)
        }
    }
    
    // MARK: - Logic for "Open App If Needed" (New Feature)
    
    private func cycleAllApps(hudItems: [HUDAppItem], group: AppGroup, store: GroupStore, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?, activeKey: KeyboardShortcuts.Key?) {
        // If the HUD is currently self-driving (looping via timer), ignore external shortcut requests (Key Repeats)
        // This prevents double-incrementing when holding the key.
        if HUDManager.shared.isLooping {
            return
        }

        // Determine the next app to activate
        var nextAppId: String

        // Check if any app from the group is currently running
        let hasRunningApp = hudItems.contains { $0.isRunning }

        // Use shared logic
        let cycleItems = hudItems.map { CyclingAppItem(id: $0.id) }
        let frontmostApp = NSWorkspace.shared.frontmostApplication

        // Build unique ID for frontmost app (bundleId-pid format)
        let frontmostAppUniqueId: String? = {
            guard let app = frontmostApp, let bundleId = app.bundleIdentifier else { return nil }
            return "\(bundleId)-\(app.processIdentifier)"
        }()

        let resolvableItems = hudItems.map { ResolvableAppItem(id: $0.id, bundleId: $0.bundleId) }
        let resolvedLastActiveId = AppCyclingLogic.resolveLastActiveId(
            storedId: group.lastActiveAppBundleId,
            items: resolvableItems
        )

        nextAppId = AppCyclingLogic.nextAppId(
            items: cycleItems,
            currentFrontmostAppId: frontmostAppUniqueId,
            currentHUDSelectionId: HUDManager.shared.currentSelectedAppId,
            lastActiveAppId: resolvedLastActiveId,
            isHUDVisible: HUDManager.shared.isVisible
        )

        // If no app from the group is running, launch the first app and show overlay
        if !hasRunningApp {
            nextAppId = hudItems[0].id
            store.updateLastActiveApp(bundleId: nextAppId, for: group.id)
            if let item = hudItems.first {
                activateOrLaunch(bundleId: item.bundleId, pid: item.pid)
                LaunchOverlayManager.shared.show(appName: item.name, appIcon: item.icon)
            }
            return
        }

        // Find the HUDAppItem for the next app
        let nextItem = hudItems.first { $0.id == nextAppId }

        // Store composite ID (e.g. "bundleId-pid") so we can identify the exact
        // instance next time. Falls back gracefully if the PID changes on restart.
        store.updateLastActiveApp(bundleId: nextItem?.id ?? nextAppId, for: group.id)

        let hudShown = showHUD(items: hudItems, activeAppId: nextAppId, modifierFlags: modifierFlags, shortcut: shortcut, activeKey: activeKey, shouldActivate: true)

        if !hudShown {
             activateOrLaunch(bundleId: nextItem?.bundleId ?? nextAppId, pid: nextItem?.pid)
        }
    }
    
    // MARK: - Legacy Logic (Only Running Apps)
    
    private func cycleRunningAppsOnly(hudItems: [HUDAppItem], group: AppGroup, store: GroupStore, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?, activeKey: KeyboardShortcuts.Key?) {
        // If the HUD is currently self-driving (looping via timer), ignore external shortcut requests (Key Repeats)
        if HUDManager.shared.isLooping {
            return
        }

        let runningItems = hudItems.filter { $0.isRunning }
        
        if runningItems.isEmpty {
            // No apps running - launch the first app and show launching overlay
            if let firstApp = group.apps.first {
                launchApp(bundleIdentifier: firstApp.bundleIdentifier)
                store.updateLastActiveApp(bundleId: firstApp.bundleIdentifier, for: group.id)
                LaunchOverlayManager.shared.show(
                    appName: firstApp.name,
                    appIcon: getIcon(for: firstApp)
                )
            }
            return
        }
        
        if runningItems.count == 1 {
            // Toggle behavior
            let item = runningItems[0]
            // Find the specific app by PID if available
            let app: NSRunningApplication? = {
                if let pid = item.pid {
                    return NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleId)
                        .first { $0.processIdentifier == pid }
                }
                return NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleId).first
            }()
            
            if app?.isActive == true {
                app?.hide()
                showHUD(
                    items: runningItems,
                    activeAppId: item.id,
                    modifierFlags: modifierFlags,
                    shortcut: shortcut,
                    activeKey: activeKey,
                    shouldActivate: false,
                    onSelect: { [weak store] selectedId in
                        Task { @MainActor in
                             store?.updateLastActiveApp(bundleId: selectedId, for: group.id)
                        }
                    }
                )
            } else {
                store.updateLastActiveApp(bundleId: item.id, for: group.id)
                let hudShown = showHUD(
                    items: runningItems,
                    activeAppId: item.id,
                    modifierFlags: modifierFlags,
                    shortcut: shortcut,
                    activeKey: activeKey,
                    onSelect: { [weak store] selectedId in
                        Task { @MainActor in
                             store?.updateLastActiveApp(bundleId: selectedId, for: group.id)
                        }
                    }
                )
                if !hudShown {
                    app?.unhide()
                    app?.activate(options: .activateAllWindows)
                }
            }
            return
        }
        
        // Cycle logic
        var nextAppId: String
        
        // Use shared logic
        let cycleItems = runningItems.map { CyclingAppItem(id: $0.id) }
        let frontmostApp = NSWorkspace.shared.frontmostApplication

        // Build unique ID for frontmost app (bundleId-pid format)
        let frontmostAppUniqueId: String? = {
            guard let app = frontmostApp, let bundleId = app.bundleIdentifier else { return nil }
            return "\(bundleId)-\(app.processIdentifier)"
        }()

        let resolvableItems = runningItems.map { ResolvableAppItem(id: $0.id, bundleId: $0.bundleId) }
        let resolvedLastActiveId = AppCyclingLogic.resolveLastActiveId(
            storedId: group.lastActiveAppBundleId,
            items: resolvableItems
        )

        nextAppId = AppCyclingLogic.nextAppId(
            items: cycleItems,
            currentFrontmostAppId: frontmostAppUniqueId,
            currentHUDSelectionId: HUDManager.shared.currentSelectedAppId,
            lastActiveAppId: resolvedLastActiveId,
            isHUDVisible: HUDManager.shared.isVisible
        )
        
        // Find the HUDAppItem for the next app
        let nextItem = runningItems.first { $0.id == nextAppId }
        
        // Store composite ID so we can identify the exact instance next time
        store.updateLastActiveApp(bundleId: nextItem?.id ?? nextAppId, for: group.id)

        let hudShown = showHUD(
            items: runningItems,
            activeAppId: nextAppId,
            modifierFlags: modifierFlags,
            shortcut: shortcut,
            activeKey: activeKey,
            onSelect: { [weak store] selectedId in
                Task { @MainActor in
                    print("[AppSwitcher] HUD selection changed to \(selectedId). Updating Store.")
                    // When HUD selection changes (loop or arrow keys), update the store!
                    // Note: We need to map the selected ID (which might be a composite) back to what the store expects.
                    // But store.updateLastActiveApp handles bundleId logic internally? No, it takes a raw string.
                    // Ideally we should find the item again to get the "correct" id if needed, but the ID passed from HUD IS the correct ID.
                    store?.updateLastActiveApp(bundleId: selectedId, for: group.id)
                }
            }
        )
        
        if !hudShown {
             activateOrLaunch(bundleId: nextItem?.bundleId ?? nextAppId, pid: nextItem?.pid)
        }
    }
    
    // MARK: - Helpers
    
    private func getHUDItems(for group: AppGroup) -> [HUDAppItem] {
        if group.shouldOpenAppIfNeeded {
            // Create items for all apps in group, with separate entries for each running instance
            var items: [HUDAppItem] = []
            for appItem in group.apps {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: appItem.bundleIdentifier)
                    .filter { $0.activationPolicy == .regular }
                
                if runningApps.isEmpty {
                    // App not running - add a single non-running item
                    items.append(HUDAppItem(
                        bundleId: appItem.bundleIdentifier,
                        name: appItem.name,
                        icon: getIcon(for: appItem)
                    ))
                } else {
                    // App has one or more running instances - add each one
                    for runningApp in runningApps {
                        items.append(HUDAppItem(
                            runningApp: runningApp,
                            name: appItem.name,
                            icon: getIcon(for: appItem)
                        ))
                    }
                }
            }
            return items
        } else {
            // Original logic: only running apps, sorted by group order, with separate entries for each instance
            let runningApps = getRunningApps(in: group)
            return runningApps.map { app in
                HUDAppItem(runningApp: app)
            }
        }
    }
    
    private func getRunningApps(in group: AppGroup) -> [NSRunningApplication] {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let groupBundleIds = Set(group.apps.map { $0.bundleIdentifier })
        
        let filteredApps = runningApps.filter { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return groupBundleIds.contains(bundleId) && app.activationPolicy == .regular
        }
        
        // Sort by group order (bundle ID order), then by PID for stable ordering of instances
        return filteredApps.sorted { app1, app2 in
            let index1 = group.apps.firstIndex { $0.bundleIdentifier == app1.bundleIdentifier } ?? Int.max
            let index2 = group.apps.firstIndex { $0.bundleIdentifier == app2.bundleIdentifier } ?? Int.max
            if index1 != index2 {
                return index1 < index2
            }
            // Same bundle ID - sort by PID for stable ordering of instances
            return app1.processIdentifier < app2.processIdentifier
        }
    }
    
    private func getIcon(for appItem: AppItem) -> NSImage? {
        IconCache.shared.getIcon(for: appItem)
    }
    
    /// Overload for direct Launch overlay use case which might pass different things?
    // The previous getIcon was for AppItem.
    // getHUDItems uses getIcon(for: appItem).
    
    /// Get the KeyboardShortcuts.Key from the shortcut
    private func getShortcutKey(for group: AppGroup) -> KeyboardShortcuts.Key? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: group.shortcutName) else {
            return nil
        }
        return shortcut.key
    }

    /// Get the NSEvent.ModifierFlags from the KeyboardShortcuts shortcut
    private func getModifierFlags(for group: AppGroup) -> NSEvent.ModifierFlags? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: group.shortcutName) else {
            return nil
        }
        return shortcut.modifiers
    }
    
    @discardableResult
    private func showHUD(items: [HUDAppItem], activeAppId: String, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?, activeKey: KeyboardShortcuts.Key? = nil, shouldActivate: Bool = true, immediate: Bool = false, onSelect: ((String) -> Void)? = nil) -> Bool {
        if UserDefaults.standard.bool(forKey: "showHUD") {
            HUDManager.shared.scheduleShow(
                items: items,
                activeAppId: activeAppId, 
                modifierFlags: modifierFlags, 
                shortcut: shortcut, 
                activeKey: activeKey, 
                shouldActivate: shouldActivate, 
                immediate: immediate, 
                onSelect: onSelect
            )
            return true
        }
        return false
    }
    
    private func activateOrLaunch(bundleId: String, pid: pid_t? = nil) {
        if let pid = pid {
            // Activate specific instance by PID
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if let app = runningApps.first(where: { $0.processIdentifier == pid }) {
                app.unhide()
                app.activate(options: .activateAllWindows)
                return
            }
        }
        // Fallback: activate by bundle ID (first match) or launch
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
             app.unhide()
             app.activate(options: .activateAllWindows)
        } else {
             launchApp(bundleIdentifier: bundleId)
        }
    }
    
    /// Launch an app by bundle identifier
    func launchApp(bundleIdentifier: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            print("Could not find app with bundle identifier: \(bundleIdentifier)")
            return
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            if let error = error {
                print("Failed to launch app: \(error)")
            }
        }
    }
}

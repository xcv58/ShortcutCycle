
import Foundation
import AppKit
import SwiftUI
import Carbon
import KeyboardShortcuts

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
        
        let hudItems = getHUDItems(for: group)

        // If "Open App If Needed" is enabled, we cycle through ALL apps
        if group.shouldOpenAppIfNeeded {
             if hudItems.isEmpty { return }
             cycleAllApps(hudItems: hudItems, group: group, store: store, modifierFlags: modifierFlags, shortcut: shortcutString)
        } else {
             // Legacy behavior: Only cycle running apps
             cycleRunningAppsOnly(hudItems: hudItems, group: group, store: store, modifierFlags: modifierFlags, shortcut: shortcutString)
        }
    }
    
    // MARK: - Logic for "Open App If Needed" (New Feature)
    
    private func cycleAllApps(hudItems: [HUDAppItem], group: AppGroup, store: GroupStore, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?) {
        // Determine the next app to activate
        var nextAppId: String

        // Check if any app from the group is currently running
        let hasRunningApp = hudItems.contains { $0.isRunning }

        // Use shared logic
        let cycleItems = hudItems.map { CyclingAppItem(id: $0.id) }
        let frontmostApp = NSWorkspace.shared.frontmostApplication

        nextAppId = AppCyclingLogic.nextAppId(
            items: cycleItems,
            currentFrontmostAppId: frontmostApp?.bundleIdentifier,
            currentHUDSelectionId: HUDManager.shared.currentSelectedAppId,
            lastActiveAppId: group.lastActiveAppBundleId,
            isHUDVisible: HUDManager.shared.isVisible
        )

        // If no app from the group is running, launch the first app and show overlay
        if !hasRunningApp {
            nextAppId = hudItems[0].id
            store.updateLastActiveApp(bundleId: nextAppId, for: group.id)
            activateOrLaunch(bundleId: nextAppId)
            if let item = hudItems.first {
                LaunchOverlayManager.shared.show(appName: item.name, appIcon: item.icon)
            }
            return
        }

        // Perform Switch
        store.updateLastActiveApp(bundleId: nextAppId, for: group.id)

        let hudShown = showHUD(items: hudItems, activeAppId: nextAppId, modifierFlags: modifierFlags, shortcut: shortcut, shouldActivate: true)

        if !hudShown {
             activateOrLaunch(bundleId: nextAppId)
        }
    }
    
    // MARK: - Legacy Logic (Only Running Apps)
    
    private func cycleRunningAppsOnly(hudItems: [HUDAppItem], group: AppGroup, store: GroupStore, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?) {
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
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: item.id).first
            
            if app?.isActive == true {
                app?.hide()
                showHUD(items: runningItems, activeAppId: item.id, modifierFlags: modifierFlags, shortcut: shortcut, shouldActivate: false)
            } else {
                store.updateLastActiveApp(bundleId: item.id, for: group.id)
                let hudShown = showHUD(items: runningItems, activeAppId: item.id, modifierFlags: modifierFlags, shortcut: shortcut)
                if !hudShown {
                    app?.activate(options: NSApplication.ActivationOptions.activateAllWindows)
                }
            }
            return
        }
        
        // Cycle logic
        var nextAppId: String
        
        // Use shared logic
        let cycleItems = runningItems.map { CyclingAppItem(id: $0.id) }
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        
        nextAppId = AppCyclingLogic.nextAppId(
            items: cycleItems,
            currentFrontmostAppId: frontmostApp?.bundleIdentifier,
            currentHUDSelectionId: HUDManager.shared.currentSelectedAppId,
            lastActiveAppId: group.lastActiveAppBundleId,
            isHUDVisible: HUDManager.shared.isVisible
        )
        
        store.updateLastActiveApp(bundleId: nextAppId, for: group.id)
        
        let hudShown = showHUD(items: runningItems, activeAppId: nextAppId, modifierFlags: modifierFlags, shortcut: shortcut)
        
        if !hudShown {
             activateOrLaunch(bundleId: nextAppId)
        }
    }
    
    // MARK: - Helpers
    
    private func getHUDItems(for group: AppGroup) -> [HUDAppItem] {
        if group.shouldOpenAppIfNeeded {
            return group.apps.map { appItem in
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: appItem.bundleIdentifier)
                let isRunning = !runningApps.isEmpty
                
                return HUDAppItem(
                    id: appItem.bundleIdentifier,
                    name: appItem.name,
                    icon: getIcon(for: appItem),
                    isRunning: isRunning
                )
            }
        } else {
            // Original logic: only running apps, sorted by group order
            let runningApps = getRunningApps(in: group)
            return runningApps.map { app in
                HUDAppItem(
                    id: app.bundleIdentifier ?? "",
                    name: app.localizedName ?? "App",
                    icon: app.icon, // NSRunningApplication doesn't behave like AppItem fully here?
                    // NSRunningApplication has .icon
                    isRunning: true
                )
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
        
        return filteredApps.sorted { app1, app2 in
            let index1 = group.apps.firstIndex { $0.bundleIdentifier == app1.bundleIdentifier } ?? Int.max
            let index2 = group.apps.firstIndex { $0.bundleIdentifier == app2.bundleIdentifier } ?? Int.max
            return index1 < index2
        }
    }
    
    private func getIcon(for appItem: AppItem) -> NSImage? {
        IconCache.shared.getIcon(for: appItem)
    }
    
    /// Overload for direct Launch overlay use case which might pass different things?
    // The previous getIcon was for AppItem.
    // getHUDItems uses getIcon(for: appItem).
    
    /// Get the NSEvent.ModifierFlags from the KeyboardShortcuts shortcut
    private func getModifierFlags(for group: AppGroup) -> NSEvent.ModifierFlags? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: group.shortcutName) else {
            return nil
        }
        return shortcut.modifiers
    }
    
    @discardableResult
    private func showHUD(items: [HUDAppItem], activeAppId: String, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?, shouldActivate: Bool = true, immediate: Bool = false) -> Bool {
        if UserDefaults.standard.bool(forKey: "showHUD") {
            HUDManager.shared.scheduleShow(items: items, activeAppId: activeAppId, modifierFlags: modifierFlags, shortcut: shortcut, shouldActivate: shouldActivate, immediate: immediate)
            return true
        }
        return false
    }
    
    private func activateOrLaunch(bundleId: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
             app.activate(options: NSApplication.ActivationOptions.activateAllWindows)
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

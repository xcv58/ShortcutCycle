import Foundation
import AppKit
import SwiftUI
import Carbon
import KeyboardShortcuts

/// Handles the core app switching logic for groups
@MainActor
class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()
    
    private init() {
        UserDefaults.standard.register(defaults: ["showHUD": true, "showShortcutInHUD": true])
    }
    
    /// Handle a shortcut activation for a given group
    func handleShortcut(for group: AppGroup, store: GroupStore) {
        let runningApps = getRunningApps(in: group)
        
        // Get modifier flags from the current shortcut using KeyboardShortcuts
        let modifierFlags = getModifierFlags(for: group)
        let shortcutString = group.shortcutDisplayString
        
        switch runningApps.count {
        case 0:
            // No apps running - launch the first app in the group
            if let firstApp = group.apps.first {
                launchApp(bundleIdentifier: firstApp.bundleIdentifier)
                store.updateLastActiveApp(bundleId: firstApp.bundleIdentifier, for: group.id)
                // Note: Can't show HUD effectively as app isn't running yet
            }
            
        case 1:
            // Only one app running - toggle between front and hidden
            let app = runningApps[0]
            if app.isActive {
                app.hide()
                showHUD(apps: runningApps, activeApp: app, modifierFlags: modifierFlags, shortcut: shortcutString, shouldActivate: false)
            } else {
                store.updateLastActiveApp(bundleId: app.bundleIdentifier ?? "", for: group.id)
                let hudShown = showHUD(apps: runningApps, activeApp: app, modifierFlags: modifierFlags, shortcut: shortcutString)
                
                if !hudShown {
                   app.activate(options: [.activateAllWindows])
                }
            }
            
        default:
            // Multiple apps running - cycle through them
            cycleApps(runningApps, group: group, store: store, modifierFlags: modifierFlags, shortcut: shortcutString)
        }
    }
    
    /// Get the NSEvent.ModifierFlags from the KeyboardShortcuts shortcut
    private func getModifierFlags(for group: AppGroup) -> NSEvent.ModifierFlags? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: group.shortcutName) else {
            return nil
        }
        return shortcut.modifiers
    }
    
    @discardableResult
    private func showHUD(apps: [NSRunningApplication], activeApp: NSRunningApplication, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?, shouldActivate: Bool = true) -> Bool {
        if UserDefaults.standard.bool(forKey: "showHUD") {
            HUDManager.shared.scheduleShow(apps: apps, activeApp: activeApp, modifierFlags: modifierFlags, shortcut: shortcut, shouldActivate: shouldActivate)
            return true
        }
        return false
    }
    
    /// Get all running apps that belong to a group, sorted by order in group
    private func getRunningApps(in group: AppGroup) -> [NSRunningApplication] {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        let groupBundleIds = Set(group.apps.map { $0.bundleIdentifier })
        
        let filteredApps = runningApps.filter { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return groupBundleIds.contains(bundleId) && app.activationPolicy == .regular
        }
        
        // Sort apps by their position in the group's app list
        return filteredApps.sorted { app1, app2 in
            let index1 = group.apps.firstIndex { $0.bundleIdentifier == app1.bundleIdentifier } ?? Int.max
            let index2 = group.apps.firstIndex { $0.bundleIdentifier == app2.bundleIdentifier } ?? Int.max
            return index1 < index2
        }
    }
    
    /// Cycle through multiple running apps
    private func cycleApps(_ apps: [NSRunningApplication], group: AppGroup, store: GroupStore, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?) {
        // Apps are already sorted by getRunningApps
        let sortedApps = apps
        
        var appToActivate: NSRunningApplication
        
        // Check if we are already cycling (HUD visible)
        // If so, use the HUD's current selection as the reference point to avoid stale state issues
        if HUDManager.shared.isVisible, let current = HUDManager.shared.currentSelectedApp {
            if let currentIndex = sortedApps.firstIndex(where: { $0.processIdentifier == current.processIdentifier }) {
                let nextIndex = (currentIndex + 1) % sortedApps.count
                appToActivate = sortedApps[nextIndex]
            } else {
                appToActivate = sortedApps[0]
            }
        } else {
            // New cycle start - check current system state
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            
            let isGroupAppActive = sortedApps.contains { $0.processIdentifier == frontmostApp?.processIdentifier }
            
            if isGroupAppActive {
                // Find the current app and switch to the next one
                if let currentIndex = sortedApps.firstIndex(where: { $0.processIdentifier == frontmostApp?.processIdentifier }) {
                    let nextIndex = (currentIndex + 1) % sortedApps.count
                    appToActivate = sortedApps[nextIndex]
                } else {
                    appToActivate = sortedApps[0]
                }
            } else {
                // No group app is frontmost - bring the last used one, or first running
                if let lastBundleId = group.lastActiveAppBundleId,
                   let lastApp = sortedApps.first(where: { $0.bundleIdentifier == lastBundleId }) {
                    appToActivate = lastApp
                } else {
                    appToActivate = sortedApps[0]
                }
            }
        }
        
        
        
        
        store.updateLastActiveApp(bundleId: appToActivate.bundleIdentifier ?? "", for: group.id)
        
        let hudShown = showHUD(apps: sortedApps, activeApp: appToActivate, modifierFlags: modifierFlags, shortcut: shortcut)
        
        if !hudShown {
            appToActivate.activate(options: [.activateAllWindows])
        }
    }
    
    /// Launch an app by bundle identifier
    private func launchApp(bundleIdentifier: String) {
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

// MARK: - HUD Components (Inline for compilation)

class HUDWindow: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
    }
}

@MainActor
class HUDManager: ObservableObject {
    static let shared = HUDManager()
    
    private var window: HUDWindow?
    private var hideTimer: Timer?
    private var showTimer: Timer?
    private var eventMonitor: Any?
    private var lastRequestTime: Date?

    private var previousFrontmostApp: NSRunningApplication?
    private var pendingActiveApp: NSRunningApplication?
    
    // Track the currently selected app in the HUD
    public private(set) var currentSelectedApp: NSRunningApplication?
    
    var isVisible: Bool {
        window?.isVisible == true
    }
    
    private init() {}
    
    /// Schedule showing the HUD with macOS Command+Tab logic
    func scheduleShow(apps: [NSRunningApplication], activeApp: NSRunningApplication, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?, shouldActivate: Bool = true) {
        // Cancel existing hide timer
        hideTimer?.invalidate()
        hideTimer = nil // Ensure we don't auto-hide while interacting
        
        let now = Date()
        let isRepeated = lastRequestTime != nil && now.timeIntervalSince(lastRequestTime!) < 0.5

        lastRequestTime = now
        
        // Store pending active app for fast switching
        self.pendingActiveApp = shouldActivate ? activeApp : nil
        
        // Capture the previous frontmost app if we aren't already visible
        // We do this BEFORE we activate ourselves
        if window?.isVisible != true {
             self.previousFrontmostApp = NSWorkspace.shared.frontmostApplication
        }
        
        // Activate our app so we can receive local events
        NSApp.activate(ignoringOtherApps: true)
        
        // Fix for "Splash" issue:
        // If the Settings window is open, activating the app brings it to the front, which is jarring.
        // We push it to the back immediately after activation if it's not the HUD.
        // We use dispatch async to ensure it happens after activation logic settles.
        DispatchQueue.main.async {
            NSApp.windows.forEach { win in
                if win !== self.window && win.isVisible {
                    // This is likely the Settings window
                    win.orderBack(nil)
                }
            }
        }
        
        // If HUD is already visible or this is a repeated hit (cycling), show/update immediately
        if (window?.isVisible == true) || isRepeated {
            showTimer?.invalidate()
            showTimer = nil
            presentHUD(apps: apps, activeApp: activeApp, shortcut: shortcut)
            startMonitoringModifiers(requiredModifiers: modifierFlags)
            return
        }
        
        // Otherwise, schedule show after a short delay (mimic "hold" to show)
        showTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in // 200ms delay
            Task { @MainActor in
                self?.presentHUD(apps: apps, activeApp: activeApp, shortcut: shortcut)
                self?.startMonitoringModifiers(requiredModifiers: modifierFlags)
            }
        }
        
        // Start monitoring immediately to cancel if released early
        startMonitoringModifiers(requiredModifiers: modifierFlags)
    }
    
    private func presentHUD(apps: [NSRunningApplication], activeApp: NSRunningApplication, shortcut: String?) {
        if window == nil {
            window = HUDWindow()
        }
        
        currentSelectedApp = activeApp
        
        guard let window = window else { return }
        
        // Update content
        let hudView = AppSwitcherHUDView(apps: apps, activeApp: activeApp, shortcutString: shortcut)
        window.contentView = NSHostingView(rootView: hudView)
        
        // Resize and center
        if let screen = NSScreen.main {
            let viewSize = window.contentView?.fittingSize ?? CGSize(width: 400, height: 150)
            let x = screen.visibleFrame.midX - viewSize.width / 2
            let y = screen.visibleFrame.midY - viewSize.height / 2
            window.setFrame(NSRect(x: x, y: y, width: viewSize.width, height: viewSize.height), display: true)
        }
        
        window.orderFront(nil)
    }
    
    private func startMonitoringModifiers(requiredModifiers: NSEvent.ModifierFlags?) {
        // Stop existing monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        guard let required = requiredModifiers, !required.isEmpty else {
            // No modifiers required? Just schedule hide after delay since we can't detect "release"
             scheduleAutoHide()
             return
        }
        
        // Check if ANY of the required modifiers are currently held.
        // This prevents the HUD from getting stuck if the keys were already released
        // before we started monitoring.
        let currentFlags = NSEvent.modifierFlags
        if !checkModifiersHeld(currentFlags: currentFlags, required: required) {
             finalizeSwitchAndHide()
             return
        }
        
        // Monitor flags changed - use LOCAL monitor now since we are active
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event: event, required: required)
            }
            return event
        }
    }
    
    private func checkModifiersHeld(currentFlags: NSEvent.ModifierFlags, required: NSEvent.ModifierFlags) -> Bool {
        if required.contains(.command) && currentFlags.contains(.command) { return true }
        if required.contains(.shift) && currentFlags.contains(.shift) { return true }
        if required.contains(.option) && currentFlags.contains(.option) { return true }
        if required.contains(.control) && currentFlags.contains(.control) { return true }
        return false
    }
    
    private func handleFlagsChanged(event: NSEvent, required: NSEvent.ModifierFlags) {
        let currentFlags = event.modifierFlags
        
        if !checkModifiersHeld(currentFlags: currentFlags, required: required) {
             finalizeSwitchAndHide()
        }
    }
    
    private func finalizeSwitchAndHide() {
        // Modifiers released
        showTimer?.invalidate() // Cancel pending show
        showTimer = nil
        
        // Fast switch: user released keys before HUD appeared or while it was visible
        if let pending = pendingActiveApp {
            pending.activate(options: [.activateAllWindows])
            pendingActiveApp = nil
        }
        
        if window?.isVisible == true {
            hide() // Hide immediately
        }
        
        // Stop monitoring
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func scheduleAutoHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }
    
    /// Hide the HUD
    func hide() {
        window?.orderOut(nil)
        window = nil
        currentSelectedApp = nil
        
        // Ensure we activate the pending app if it exists (fallback)
        if let pending = pendingActiveApp {
            pending.activate(options: [.activateAllWindows])
            pendingActiveApp = nil
        }
        
        if NSApp.isActive {
            NSApp.hide(nil) // Yield focus back
        }
        
        hideTimer?.invalidate()
        hideTimer = nil
        showTimer?.invalidate()
        showTimer = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

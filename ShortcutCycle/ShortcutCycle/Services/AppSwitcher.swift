import Foundation
import AppKit
import SwiftUI
import Carbon

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
                showHUD(apps: runningApps, activeApp: app, modifiers: group.shortcut?.modifiers, shortcut: group.shortcut?.displayString)
            } else {
                app.activate(options: [])
                store.updateLastActiveApp(bundleId: app.bundleIdentifier ?? "", for: group.id)
                showHUD(apps: runningApps, activeApp: app, modifiers: group.shortcut?.modifiers, shortcut: group.shortcut?.displayString)
            }
            
        default:
            // Multiple apps running - cycle through them
            cycleApps(runningApps, group: group, store: store)
        }
    }
    
    private func showHUD(apps: [NSRunningApplication], activeApp: NSRunningApplication, modifiers: UInt32?, shortcut: String?) {
        if UserDefaults.standard.bool(forKey: "showHUD") {
            HUDManager.shared.scheduleShow(apps: apps, activeApp: activeApp, modifiers: modifiers, shortcut: shortcut)
        }
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
    private func cycleApps(_ apps: [NSRunningApplication], group: AppGroup, store: GroupStore) {
        // Apps are already sorted by getRunningApps
        let sortedApps = apps
        
        // Check if any app in the group is currently frontmost
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let isGroupAppActive = sortedApps.contains { $0.processIdentifier == frontmostApp?.processIdentifier }
        
        var appToActivate: NSRunningApplication
        
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
        
        appToActivate.activate(options: [])
        store.updateLastActiveApp(bundleId: appToActivate.bundleIdentifier ?? "", for: group.id)
        showHUD(apps: sortedApps, activeApp: appToActivate, modifiers: group.shortcut?.modifiers, shortcut: group.shortcut?.displayString)
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
    
    private init() {}
    
    /// Schedule showing the HUD with macOS Command+Tab logic
    func scheduleShow(apps: [NSRunningApplication], activeApp: NSRunningApplication, modifiers: UInt32?, shortcut: String?) {
        // Cancel existing hide timer
        hideTimer?.invalidate()
        hideTimer = nil // Ensure we don't auto-hide while interacting
        
        let now = Date()
        let isRepeated = lastRequestTime != nil && now.timeIntervalSince(lastRequestTime!) < 0.5
        lastRequestTime = now
        
        // If HUD is already visible or this is a repeated hit (cycling), show/update immediately
        if (window?.isVisible == true) || isRepeated {
            showTimer?.invalidate()
            showTimer = nil
            presentHUD(apps: apps, activeApp: activeApp, shortcut: shortcut)
            startMonitoringModifiers(requiredModifiers: modifiers)
            return
        }
        
        // Otherwise, schedule show after a short delay (mimic "hold" to show)
        showTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in // 200ms delay
            Task { @MainActor in
                self?.presentHUD(apps: apps, activeApp: activeApp, shortcut: shortcut)
                self?.startMonitoringModifiers(requiredModifiers: modifiers)
            }
        }
        
        // Start monitoring immediately to cancel if released early
        startMonitoringModifiers(requiredModifiers: modifiers)
    }
    
    private func presentHUD(apps: [NSRunningApplication], activeApp: NSRunningApplication, shortcut: String?) {
        if window == nil {
            window = HUDWindow()
        }
        
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
    
    private func startMonitoringModifiers(requiredModifiers: UInt32?) {
        // Stop existing monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        guard let required = requiredModifiers, required > 0 else {
            // No modifiers required? Just schedule hide after delay since we can't detect "release"
             scheduleAutoHide()
             return
        }
        
        // Monitor flags changed
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event: event, required: required)
            }
        }
    }
    
    private func handleFlagsChanged(event: NSEvent, required: UInt32) {
        let currentFlags = event.modifierFlags
        
        // Check if ANY of the required modifiers are still held.
        // If the user releases the main modifier (e.g. Command), we hide.
        // Carbon modifiers: cmdKey=256, shiftKey=512, optionKey=2048, controlKey=4096
        
        var isHeld = false
        if (required & UInt32(cmdKey) != 0) && currentFlags.contains(.command) { isHeld = true }
        if (required & UInt32(shiftKey) != 0) && currentFlags.contains(.shift) { isHeld = true }
        if (required & UInt32(optionKey) != 0) && currentFlags.contains(.option) { isHeld = true }
        if (required & UInt32(controlKey) != 0) && currentFlags.contains(.control) { isHeld = true }
        
        if !isHeld {
            // Modifiers released
            showTimer?.invalidate() // Cancel pending show
            showTimer = nil
            
            if window?.isVisible == true {
                hide() // Hide immediately
            }
            
            // Stop monitoring
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
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

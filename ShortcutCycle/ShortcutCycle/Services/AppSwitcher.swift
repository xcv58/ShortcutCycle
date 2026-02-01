import Foundation
import AppKit
import SwiftUI
import Carbon
import KeyboardShortcuts
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

/// Handles the core app switching logic for groups
@MainActor
class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()
    
    // Cache for app icons to improve performance
    private var iconCache: [String: NSImage] = [:]
    
    private init() {
        UserDefaults.standard.register(defaults: ["showHUD": true, "showShortcutInHUD": true])
    }
    
    /// Handle a shortcut activation for a given group
    func handleShortcut(for group: AppGroup, store: GroupStore) {
        let modifierFlags = getModifierFlags(for: group)
        let shortcutString = group.shortcutDisplayString
        
        let hudItems = getHUDItems(for: group)
        
        if hudItems.isEmpty { return }
        
        // If "Open App If Needed" is enabled, we cycle through ALL apps
        if group.shouldOpenAppIfNeeded {
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

        // If no app from the group is running, always select the first app
        if !hasRunningApp {
            nextAppId = hudItems[0].id
        }

        // Perform Switch
        store.updateLastActiveApp(bundleId: nextAppId, for: group.id)

        // We always want to activate the selected app eventually.
        // If HUD is shown, it will handle activation lazily (on key release).
        // If HUD is disabled, we activate immediately.
        // Show HUD immediately (skip delay) when no app from the group is running.
        let hudShown = showHUD(items: hudItems, activeAppId: nextAppId, modifierFlags: modifierFlags, shortcut: shortcut, shouldActivate: true, immediate: !hasRunningApp)

        if !hudShown {
             activateOrLaunch(bundleId: nextAppId)
        }
    }
    
    // MARK: - Legacy Logic (Only Running Apps)
    
    private func cycleRunningAppsOnly(hudItems: [HUDAppItem], group: AppGroup, store: GroupStore, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?) {
        let runningItems = hudItems.filter { $0.isRunning }
        
        if runningItems.isEmpty {
            // No apps running - launch the first app and show HUD immediately
            if let firstApp = group.apps.first {
                launchApp(bundleIdentifier: firstApp.bundleIdentifier)
                store.updateLastActiveApp(bundleId: firstApp.bundleIdentifier, for: group.id)
                let firstItem = HUDAppItem(
                    id: firstApp.bundleIdentifier,
                    name: firstApp.name,
                    icon: getIcon(for: firstApp),
                    isRunning: false
                )
                showHUD(items: [firstItem], activeAppId: firstApp.bundleIdentifier, modifierFlags: modifierFlags, shortcut: shortcut, shouldActivate: false, immediate: true)
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
                    app?.activate(options: [.activateAllWindows])
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
                    icon: app.icon,
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
        if let cached = iconCache[appItem.bundleIdentifier] {
            return cached
        }
        
        var icon: NSImage?
        
        // Try to get icon from running app first (most accurate)
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: appItem.bundleIdentifier).first {
            icon = runningApp.icon
        }
        
        // Try path
        if icon == nil, let path = appItem.iconPath {
             icon = NSWorkspace.shared.icon(forFile: path)
        }
        
        // Try finding app by bundle ID
        if icon == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appItem.bundleIdentifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
        
        if let icon = icon {
            iconCache[appItem.bundleIdentifier] = icon
        }
        
        return icon
    }
    
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
             app.activate(options: [.activateAllWindows])
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
        self.ignoresMouseEvents = false // Enable mouse events for selection
    }
}

@MainActor
class HUDManager: ObservableObject {
    static let shared = HUDManager()
    
    private var window: HUDWindow?
    private var hideTimer: Timer?
    private var showTimer: Timer?
    private var eventMonitors: [Any] = []
    private var appResignObserver: NSObjectProtocol?
    private var lastRequestTime: Date?
    
    private var currentItems: [HUDAppItem] = []

    private var previousFrontmostApp: NSRunningApplication?
    private var pendingActiveAppId: String?
    
    // Track the currently selected app in the HUD
    public private(set) var currentSelectedAppId: String?
    
    var isVisible: Bool {
        window?.isVisible == true
    }
    
    private init() {}
    
    /// Schedule showing the HUD with macOS Command+Tab logic
    func scheduleShow(items: [HUDAppItem], activeAppId: String, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?, shouldActivate: Bool = true, immediate: Bool = false) {
        // Cancel existing hide timer
        hideTimer?.invalidate()
        hideTimer = nil // Ensure we don't auto-hide while interacting
        
        let now = Date()
        let isRepeated = lastRequestTime != nil && now.timeIntervalSince(lastRequestTime!) < 0.5

        lastRequestTime = now
        
        // Store pending active app for fast switching
        self.pendingActiveAppId = shouldActivate ? activeAppId : nil
        
        // Capture the previous frontmost app if we aren't already visible
        // We do this BEFORE we activate ourselves
        if window?.isVisible != true {
             self.previousFrontmostApp = NSWorkspace.shared.frontmostApplication
        }
        
        // Activate our app so we can receive local events
        NSApp.activate(ignoringOtherApps: true)
        
        // Fix for "Splash" issue:
        DispatchQueue.main.async {
            NSApp.windows.forEach { win in
                if win !== self.window && win.isVisible {
                    win.orderBack(nil)
                }
            }
        }
        
        // If HUD is already visible, this is a repeated hit (cycling), or immediate is requested, show/update immediately
        if (window?.isVisible == true) || isRepeated || immediate {
            showTimer?.invalidate()
            showTimer = nil
            presentHUD(items: items, activeAppId: activeAppId, shortcut: shortcut)
            startMonitoringModifiers(requiredModifiers: modifierFlags)
            return
        }
        
        // Otherwise, schedule show after a short delay (mimic "hold" to show)
        showTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in // 200ms delay
            Task { @MainActor in
                self?.presentHUD(items: items, activeAppId: activeAppId, shortcut: shortcut)
                self?.startMonitoringModifiers(requiredModifiers: modifierFlags)
            }
        }
        
        // Start monitoring immediately to cancel if released early
        startMonitoringModifiers(requiredModifiers: modifierFlags)
    }
    
    private func presentHUD(items: [HUDAppItem], activeAppId: String, shortcut: String?) {
        if window == nil {
            window = HUDWindow()
        }
        
        self.currentItems = items
        currentSelectedAppId = activeAppId
        
        guard let window = window else { return }
        
        // Update content
        var hudView = AppSwitcherHUDView(apps: items, activeAppId: activeAppId, shortcutString: shortcut)
        
        // Handle selection from UI (click)
        hudView.onSelect = { [weak self] selectedId in
            Task { @MainActor in
                // Set pending active app to the selected one, so hide() activates the correct app
                self?.pendingActiveAppId = selectedId
                self?.hide()
            }
        }
        
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
        // Stop existing monitors
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }
        
        guard let required = requiredModifiers, !required.isEmpty else {
            // No modifiers required? Just schedule hide after delay since we can't detect "release"
             scheduleAutoHide()
             return
        }
        
        // Check if ANY of the required modifiers are currently held.
        let currentFlags = NSEvent.modifierFlags
        if !checkModifiersHeld(currentFlags: currentFlags, required: required) {
             finalizeSwitchAndHide()
             return
        }
        
        // Monitor flags changed - use LOCAL monitor now since we are active
        let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event: event, required: required)
            }
            return event
        }
        eventMonitors.append(flagsMonitor)
        
        // Monitor Arrow Keys for navigation
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            return self?.handleKeyDown(event: event) ?? event
        }
        eventMonitors.append(keyMonitor)
        
        // Monitor Click Away (Focus Loss)
        appResignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.hide()
        }
    }
    
    private func handleKeyDown(event: NSEvent) -> NSEvent? {
        guard let currentId = currentSelectedAppId,
              let currentIndex = currentItems.firstIndex(where: { $0.id == currentId }) else {
            return event
        }
        
        var nextIndex = currentIndex
        let count = currentItems.count
        let isGrid = count > 9
        let columns = 5
        
        switch event.keyCode {
        case 123: // Left
            nextIndex = (currentIndex - 1 + count) % count
        case 124: // Right
            nextIndex = (currentIndex + 1) % count
        case 125: // Down
            if isGrid {
                let candidate = currentIndex + columns
                if candidate < count { nextIndex = candidate }
            } else {
                 nextIndex = (currentIndex + 1) % count
            }
        case 126: // Up
            if isGrid {
                let candidate = currentIndex - columns
                if candidate >= 0 { nextIndex = candidate }
            } else {
                nextIndex = (currentIndex - 1 + count) % count
            }
        default:
            return event
        }
        
        if nextIndex != currentIndex {
            let newId = currentItems[nextIndex].id
            presentHUD(items: currentItems, activeAppId: newId, shortcut: nil)
            self.pendingActiveAppId = newId
            return nil // Consume event
        }
        
        return event
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
        if let pendingId = pendingActiveAppId {
            activateOrLaunch(bundleId: pendingId)
            pendingActiveAppId = nil
        }
        
        if window?.isVisible == true {
            hide() // Hide immediately
        }
        
        // Stop monitoring
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }
    }
    
    private func activateOrLaunch(bundleId: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
             app.activate(options: [.activateAllWindows])
        } else {
             // Use AppSwitcher shared helper to launch
             AppSwitcher.shared.launchApp(bundleIdentifier: bundleId)
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
        currentSelectedAppId = nil
        
        // Ensure we activate the pending app if it exists (fallback)
        if let pendingId = pendingActiveAppId {
            activateOrLaunch(bundleId: pendingId)
            pendingActiveAppId = nil
        }
        
        if NSApp.isActive {
            NSApp.hide(nil) // Yield focus back
        }
        
        hideTimer?.invalidate()
        hideTimer = nil
        showTimer?.invalidate()
        showTimer = nil
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }
    }
}

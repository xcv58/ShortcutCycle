import Foundation
import AppKit
import SwiftUI
import CoreGraphics
import KeyboardShortcuts
import Combine

// MARK: - Dependency Injection Protocols

protocol TimeProvider {
    var now: Date { get }
}

class SystemTimeProvider: TimeProvider {
    var now: Date { Date() }
}

protocol TimerScheduler {
    func schedule(timeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer
}

class SystemTimerScheduler: TimerScheduler {
    func schedule(timeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        return Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: repeats, block: block)
    }
}

// MARK: - HUD Window

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

// MARK: - HUD Manager

@MainActor
class HUDManager: ObservableObject {
    static let shared = HUDManager()
    
    let objectWillChange = ObservableObjectPublisher()
    
    // Dependencies
    var timeProvider: TimeProvider = SystemTimeProvider()
    var timerScheduler: TimerScheduler = SystemTimerScheduler()
    
    private var window: HUDWindow?
    private var hideTimer: Timer?
    private var showTimer: Timer?
    private var loopTimer: Timer?
    private var keyUpMonitor: Any?
    private var eventMonitors: [Any] = []
    private var appResignObserver: NSObjectProtocol?
    
    // Internal state for testing
    internal var lastRequestTime: Date?
    private var lastLocalKeyDownTime: Date?
    
    private var currentItems: [HUDAppItem] = []

    private var previousFrontmostApp: NSRunningApplication?
    private var pendingActiveAppId: String?
    
    // Track the currently selected app in the HUD
    public private(set) var currentSelectedAppId: String?
    private var currentShortcut: String?
    
    var isVisible: Bool {
        window?.isVisible == true
    }
    
    var isLooping: Bool {
        return loopTimer != nil
    }
    
    // Singleton extraction for testing? 
    // Ideally we should make the constructor accessible for tests, 
    // but for now we'll stick to shared instance or property injection.
    private init() {}
    
    private var onSelectCallback: ((String) -> Void)?
    
    /// Schedule showing the HUD with macOS Command+Tab logic
    func scheduleShow(items: [HUDAppItem], activeAppId: String, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?, activeKey: KeyboardShortcuts.Key? = nil, shouldActivate: Bool = true, immediate: Bool = false, onSelect: ((String) -> Void)? = nil) {
        // Cancel existing hide timer
        hideTimer?.invalidate()
        hideTimer = nil // Ensure we don't auto-hide while interacting
        
        // Update callback
        self.onSelectCallback = onSelect
        
        let now = timeProvider.now
        let isRepeated = lastRequestTime != nil && now.timeIntervalSince(lastRequestTime!) < 0.5

        lastRequestTime = now
        
        // Store pending active app for fast switching
        self.pendingActiveAppId = shouldActivate ? activeAppId : nil
        
        // Store items immediately so fast switch path can look up PID
        self.currentItems = items
        
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
            print("[HUDManager] scheduleShow: Immediate/Repeated path")
            showTimer?.invalidate()
            showTimer = nil
            presentHUD(items: items, activeAppId: activeAppId, shortcut: shortcut, activeKey: activeKey)
            startMonitoringModifiers(requiredModifiers: modifierFlags, activeKey: activeKey)
            return
        }
        
        // Otherwise, schedule show after a short delay (mimic "hold" to show)
        print("[HUDManager] scheduleShow: Scheduling delayed show (not visible/repeated)")
        showTimer?.invalidate()
        showTimer = timerScheduler.schedule(timeInterval: 0.2, repeats: false) { [weak self] _ in // 200ms delay
            print("[HUDManager] showTimer fired")
            Task { @MainActor in
                self?.presentHUD(items: items, activeAppId: activeAppId, shortcut: shortcut, activeKey: activeKey)
                self?.startMonitoringModifiers(requiredModifiers: modifierFlags, activeKey: activeKey)
            }
        }
        
        // Start monitoring immediately to cancel if released early
        print("[HUDManager] scheduleShow: Calling startMonitoringModifiers immediately")
        startMonitoringModifiers(requiredModifiers: modifierFlags, activeKey: activeKey)
    }
    
    private func presentHUD(items: [HUDAppItem], activeAppId: String, shortcut: String?, activeKey: KeyboardShortcuts.Key?) {
        // Prepare Window if needed
        if window == nil {
            window = HUDWindow()
        }
        
        self.currentItems = items
        currentSelectedAppId = activeAppId
        
        if let shortcut = shortcut {
            self.currentShortcut = shortcut
        }
        
        guard let window = window else { return }
        
        // Update content
        var hudView = AppSwitcherHUDView(apps: items, activeAppId: activeAppId, shortcutString: self.currentShortcut)
        
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
            
            // Always force center on screen to prevent drift/bumps
            let x = screen.visibleFrame.midX - viewSize.width / 2
            let y = screen.visibleFrame.midY - viewSize.height / 2
            window.setFrame(NSRect(x: x, y: y, width: viewSize.width, height: viewSize.height), display: true)
        }
        
        window.orderFront(nil)
        
        // If we have an active key loop AND the key is still held, schedule the loop timer NOW.
        // This ensures the loop "follows" the HUD visibility.
        if activeKey != nil {
             scheduleLoopStart()
        }
    }
    
    private func scheduleLoopStart() {
        guard isLoopKeyHeld else {
            print("[HUDManager] scheduleLoopStart: Key not held, aborting loop start.")
            return
        }
        
        print("[HUDManager] scheduleLoopStart: Scheduling loop timer (delayed).")
        loopTimer?.invalidate()
        // Wait 0.2s after HUD appears before starting the auto-cycle
        loopTimer = timerScheduler.schedule(timeInterval: 0.2, repeats: false) { [weak self] _ in 
             print("[HUDManager] Loop delay finished. Starting repeating loop.")
             Task { @MainActor in
                 self?.startRepeatingLoop()
             }
         }
    }
    
    private var currentLoopKey: Int? // Trace which key is currently driving the loop
    
    private var isLoopKeyHeld: Bool = false
    
    private func startMonitoringModifiers(requiredModifiers: NSEvent.ModifierFlags?, activeKey: KeyboardShortcuts.Key? = nil) {
        
        // Check if we are already looping for this key. If so, DO NOT reset monitors.
        if let active = activeKey, let current = currentLoopKey, active.rawValue == current, loopTimer != nil {
            print("[HUDManager] Already looping for key \(active.rawValue). Ignoring restart request.")
            return
        }
        
        print("[HUDManager] startMonitoringModifiers called. activeKey=\(activeKey?.rawValue ?? -1)")
        
        // Stop existing monitors
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        
        if let keyMonitor = keyUpMonitor {
            NSEvent.removeMonitor(keyMonitor)
            keyUpMonitor = nil
        }
        loopTimer?.invalidate()
        loopTimer = nil
        currentLoopKey = nil
        isLoopKeyHeld = false
        
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }
        
        // 1. Modifiers Logic
        guard let required = requiredModifiers, !required.isEmpty else {
            // No modifiers required? Just schedule hide after delay since we can't detect "release"
             scheduleAutoHide()
             return
        }
        
        // Check if ANY of the required modifiers are currently held.
        let currentFlags = NSEvent.modifierFlags
        if !checkModifiersHeld(currentFlags: currentFlags, required: required) {
             print("[HUDManager] Modifiers NOT held initially. Scheduling re-check in 50ms (Grace Period). Current=\(currentFlags.rawValue)")
             // Do NOT finalize immediately. Give it a tiny grace period for state to settle or for fast release.
             // If user really isn't holding them, the re-check will kill it.
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                 guard let self = self else { return }
                 let flags = NSEvent.modifierFlags
                 if !self.checkModifiersHeld(currentFlags: flags, required: required) {
                     print("[HUDManager] Grace Period Re-Check: Modifiers STILL not held. Finalizing. Flags=\(flags.rawValue)")
                     self.finalizeSwitchAndHide()
                 } else {
                     print("[HUDManager] Grace Period Re-Check: Modifiers detected! Continuing.")
                 }
             }
        }
        
        // Monitor flags changed - use LOCAL monitor now since we are active
        let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event: event, required: required)
            }
            return event
        }
        if let flagsMonitor = flagsMonitor {
            eventMonitors.append(flagsMonitor)
        }
        
        // 2. Loop Logic (Hyper Key / Hold Key)
        if let activeKey = activeKey {
            print("[HUDManager] Setting up loop logic for key: \(activeKey.rawValue)")
            currentLoopKey = activeKey.rawValue
            isLoopKeyHeld = true
            
            // Start listening for Key Up of this specific key
            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                let keyCode = Int(event.keyCode)
                 print("[HUDManager] KeyUp detected: \(keyCode)")
                if keyCode == activeKey.rawValue {
                    print("[HUDManager] Target key released.")
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.isLoopKeyHeld = false
                        
                        // Check if HUD is waiting to show?
                        if let timer = self.showTimer, timer.isValid {
                            // "Quick Tap" OR "Peek"? Check Modifiers!
                            let currentFlags = NSEvent.modifierFlags
                            if self.checkModifiersHeld(currentFlags: currentFlags, required: required) {
                                // Modifiers HELD -> PEEK Mode!
                                // Show HUD immediately, but DO NOT start looping (since key is up).
                                print("[HUDManager] Key released (Peek Mode). Showing HUD immediately.")
                                self.showTimer?.fire() // Trigger manual fire to show HUD
                            } else {
                                // Modifiers RELEASED -> Quick Tap!
                                // Cancel HUD.
                                print("[HUDManager] Key released (Quick Tap). Cancelling HUD.")
                                self.showTimer?.invalidate()
                                self.showTimer = nil
                            }
                        }
                        
                        self.stopLooping()
                    }
                }
                return event
            }
            // Note: Loop timer is NOT started here anymore. It's started by presentHUD -> scheduleLoopStart.
            
        } else {
             print("[HUDManager] No active key provided for looping.")
        }
        
        // Monitor Arrow Keys AND Loop Key for "Heartbeat"
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            
            // Heartbeat: If this is the active loop key, update the timestamp
            if let active = activeKey, Int(event.keyCode) == active.rawValue {
                // print("[HUDManager] Local KeyDown heartbeat for \(active.rawValue)")
                self?.lastLocalKeyDownTime = self?.timeProvider.now
                return nil // Consume the event so it doesn't beep or do other things
            }
            
            // Stop looping if user calculates manually navigation (Arrows, etc)
            // But NOT if it's just the loop key repeating!
            if let active = activeKey, Int(event.keyCode) != active.rawValue {
                self?.stopLooping()
            } else if activeKey == nil {
                self?.stopLooping()
            }
            
            return self?.handleKeyDown(event: event) ?? event
        }
        if let keyMonitor = keyMonitor {
             eventMonitors.append(keyMonitor)
        }
        
        // Monitor Click Away (Focus Loss)
        appResignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                 self?.hide()
            }
        }
    }
    
    private func startRepeatingLoop() {
        print("[HUDManager] startRepeatingLoop called")
        loopTimer?.invalidate()
        // Repeat every 0.2s
        loopTimer = timerScheduler.schedule(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.selectNextApp()
            }
        }
    }
    
    private func stopLooping() {
        print("[HUDManager] Stopping loop.")
        loopTimer?.invalidate()
        loopTimer = nil
        currentLoopKey = nil // Reset so we accept new requests
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
    }
    
    private func selectNextApp() {
        print("[HUDManager] selectNextApp triggered")
        
        // Safety Check: Is the key still held?
        if let key = currentLoopKey {
            // Check 1: Hardware State (HID)
            let isDown = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(key))
            
            // Check 2: Global Shortcut "Heartbeat" (if system repeats shortcuts)
            let isGlobalRepeat = lastRequestTime != nil && timeProvider.now.timeIntervalSince(lastRequestTime!) < 0.5
            
            // Check 3: Local KeyDown "Heartbeat" (if HUD receives key events)
            let isLocalRepeat = lastLocalKeyDownTime != nil && timeProvider.now.timeIntervalSince(lastLocalKeyDownTime!) < 0.5
            
            // If ANY is true, we consider the loop valid.
            if !isDown && !isGlobalRepeat && !isLocalRepeat {
                print("[HUDManager] Key \(key) not held (HID=\(isDown)) AND no repeats (Global=\(isGlobalRepeat), Local=\(isLocalRepeat)). Stopping loop.")
                stopLooping()
                return
            } else if !isDown {
                 // print("[HUDManager] HID says UP, but Repeat is ACTIVE. Continuing loop.")
            }
        }

        guard let currentId = currentSelectedAppId,
              let currentIndex = currentItems.firstIndex(where: { $0.id == currentId }) else {
            return
        }
        
        let count = currentItems.count
        guard count > 1 else { return }
        
        let nextIndex = (currentIndex + 1) % count
        let newId = currentItems[nextIndex].id
        
        presentHUD(items: currentItems, activeAppId: newId, shortcut: nil, activeKey: nil) // activeKey nil to avoid restarting loop logic recursion?
        
        // Update pending ID and notify listener
        self.pendingActiveAppId = newId
        self.onSelectCallback?(newId)
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
            presentHUD(items: currentItems, activeAppId: newId, shortcut: nil, activeKey: nil)
            self.pendingActiveAppId = newId
            self.onSelectCallback?(newId)
            return nil // Consume event
        }
        
        return event
    }
    
    private func isKeyDown(_ keyCode: Int) -> Bool {
        return CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode))
    }

    private func checkModifiersHeld(currentFlags: NSEvent.ModifierFlags, required: NSEvent.ModifierFlags) -> Bool {
        print("[HUDManager] checkModifiersHeld (Hardware Check)")
        
        // Command (55, 54)
        if required.contains(.command) {
            if isKeyDown(55) || isKeyDown(54) { return true }
        }
        
        // Option (58, 61)
        if required.contains(.option) {
            if isKeyDown(58) || isKeyDown(61) { return true }
        }
        
        // Control (59, 62)
        if required.contains(.control) {
            if isKeyDown(59) || isKeyDown(62) { return true }
        }
        
        // Shift (56, 60)
        if required.contains(.shift) {
            if isKeyDown(56) || isKeyDown(60) { return true }
        }
        
        // Fallback to flags if hardware check fails (unlikely, but safe)
        if required.contains(.command) && currentFlags.contains(.command) { return true }
        if required.contains(.shift) && currentFlags.contains(.shift) { return true }
        if required.contains(.option) && currentFlags.contains(.option) { return true }
        if required.contains(.control) && currentFlags.contains(.control) { return true }
        
        return false
    }
    
    private func handleFlagsChanged(event: NSEvent, required: NSEvent.ModifierFlags) {
        let currentFlags = event.modifierFlags
        print("[HUDManager] handleFlagsChanged: Flags=\(currentFlags.rawValue)")
        
        if !checkModifiersHeld(currentFlags: currentFlags, required: required) {
             print("[HUDManager] handleFlagsChanged: Modifiers released. Finalizing.")
             finalizeSwitchAndHide()
        }
    }
    
    private func finalizeSwitchAndHide() {
        print("[HUDManager] finalizeSwitchAndHide called")
        // Modifiers released
        showTimer?.invalidate() // Cancel pending show
        showTimer = nil
        
        // KEY CHANGE: Session has ended.
        // Clear the lastRequestTime tracking so the next interaction is fresh.
        lastRequestTime = nil

        stopLooping() // Ensure loop timer and monitor are cleaned up
        
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
        // Try to find the item in currentItems to get PID and real bundle ID.
        // `bundleId` parameter may be a composite "bundleId-pid" string, so we
        // resolve the real bundle identifier via currentItems to ensure macOS
        // APIs receive a valid bundle identifier in all fallback paths.
        let item = currentItems.first(where: { $0.id == bundleId || $0.bundleId == bundleId })
        let realBundleId = item?.bundleId ?? bundleId

        if let pid = item?.pid {
            // Activate specific instance by PID
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: realBundleId)
            if let app = runningApps.first(where: { $0.processIdentifier == pid }) {
                app.unhide()
                app.activate(options: .activateAllWindows)
                return
            }
        }
        // Fallback: activate by real bundle ID (first match) or launch
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: realBundleId).first {
             app.unhide()
             app.activate(options: .activateAllWindows)
        } else {
             launchApp(bundleIdentifier: realBundleId)
        }
    }
    
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
    
    private func scheduleAutoHide() {
        hideTimer?.invalidate()
        hideTimer = timerScheduler.schedule(timeInterval: 1.0, repeats: false) { [weak self] _ in
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
        currentShortcut = nil
        
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
        stopLooping()
        
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

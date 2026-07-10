import Foundation
import AppKit
import SwiftUI
import CoreGraphics
import KeyboardShortcuts
import Combine
import OSLog
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

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

typealias LocalEventMonitorRegistrar = (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?
typealias GlobalEventMonitorRegistrar = (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?

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
        self.ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool {
        true
    }
}

// MARK: - HUD Manager

@MainActor
class HUDManager: @preconcurrency ObservableObject {
    private enum HUDSessionPhase {
        case idle
        case preparedInvisible
        case revealed
    }

    static let shared = HUDManager()
    
    let objectWillChange = ObservableObjectPublisher()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ShortcutCycle", category: "HUD")
    
    // Dependencies
    var timeProvider: TimeProvider = SystemTimeProvider()
    var timerScheduler: TimerScheduler = SystemTimerScheduler()
    var presentHUDWindow: (NSWindow) -> Void = { window in
        window.orderFrontRegardless()
        window.makeKey()
    }
    var addLocalEventMonitor: LocalEventMonitorRegistrar = { mask, handler in
        NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }
    var addGlobalEventMonitor: GlobalEventMonitorRegistrar = { mask, handler in
        NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    var removeEventMonitor: (Any) -> Void = { monitor in
        NSEvent.removeMonitor(monitor)
    }
    var currentModifierFlags: () -> NSEvent.ModifierFlags = {
        NSEvent.modifierFlags
    }
    var isKeyCurrentlyDown: (Int) -> Bool = { keyCode in
        CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode))
    }
    var isAppActive: () -> Bool = {
        NSApp?.isActive == true
    }
    var settingsWindowsProvider: () -> [NSWindow] = {
        NSApp?.windows ?? []
    }
    var closeWindow: (NSWindow) -> Void = { window in
        window.close()
    }
    var setWindowAlpha: (NSWindow, CGFloat) -> Void = { window, alpha in
        window.alphaValue = alpha
    }
    var animateWindowAlpha: (NSWindow, CGFloat, TimeInterval) -> Void = { window, alpha, duration in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            window.animator().alphaValue = alpha
        }
    }
    var setWindowIgnoresMouseEvents: (NSWindow, Bool) -> Void = { window, ignores in
        window.ignoresMouseEvents = ignores
    }
    var runningApplicationsProvider: (String) -> [NSRunningApplication] = { bundleId in
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    }
    var unhideRunningApplication: (NSRunningApplication) -> Void = { app in
        app.unhide()
    }
    var yieldActivationToRunningApplication: (NSRunningApplication) -> Void = { app in
        NSApp?.yieldActivation(to: app)
    }
    var activateRunningApplication: (NSRunningApplication, Bool) -> Bool = { app, fromCurrentApp in
        if fromCurrentApp {
            return app.activate(from: .current, options: .activateAllWindows)
        }

        return app.activate(options: .activateAllWindows)
    }
    var scheduleActivationRetry: (@escaping @MainActor @Sendable () -> Void) -> Void = { action in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Task { @MainActor in
                action()
            }
        }
    }
    var scheduleVisibleWindowRecheck: (@escaping @MainActor @Sendable () -> Void) -> Void = { action in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task { @MainActor in
                action()
            }
        }
    }
    // `lazy` because the default captures `self` to call the private `activateOrLaunch` method.
    lazy var activatePendingTargetApp: (String) -> Void = { [weak self] bundleId in
        self?.activateOrLaunch(bundleId: bundleId)
    }
    // `lazy` because the default captures `self` to call the private `hasVisibleWindows` method.
    lazy var hasVisibleWindowsForPID: (pid_t) -> Bool = { [weak self] pid in
        self?.hasVisibleWindows(pid: pid) ?? true
    }
    // `lazy` because the default captures `self` to call the visibility provider.
    lazy var targetLeavesCurrentSpace: (HUDAppItem) -> Bool = { [weak self] item in
        guard let self, let pid = item.pid else {
            return false
        }

        return !self.hasVisibleWindowsForPID(pid)
    }
    
    private var window: HUDWindow?
    private var hideTimer: Timer?
    private var revealTimer: Timer?
    private var loopTimer: Timer?
    private var keyUpMonitors: [Any] = []
    private var eventMonitors: [Any] = []
    private var appResignObserver: NSObjectProtocol?
    private var activationAttemptGeneration = 0
    
    // Internal state for testing
    internal var lastRequestTime: Date?
    private var lastLocalKeyDownTime: Date?
    
    private var currentItems: [HUDAppItem] = []

    private var pendingActiveAppId: String?
    private var sessionPhase: HUDSessionPhase = .idle
    
    // Track the currently selected app in the HUD
    public private(set) var currentSelectedAppId: String?
    private var currentShortcut: String?
    
    var isVisible: Bool {
        sessionPhase == .revealed
    }

    var isSessionActive: Bool {
        sessionPhase != .idle
    }
    
    /// True only when the repeating auto-cycle loop is active (not during the initial delay phase).
    /// During the 200ms delay before auto-cycling starts, this remains false so that
    /// manual taps are still processed by AppSwitcher.
    // Internal for @testable import access in PressAndHoldTests
    internal var isRepeatingLoopActive: Bool = false

    var isLooping: Bool {
        return isRepeatingLoopActive
    }
    
    // Singleton extraction for testing? 
    // Ideally we should make the constructor accessible for tests, 
    // but for now we'll stick to shared instance or property injection.
    private init() {}
    
    private var onSelectCallback: ((String) -> Void)?
    private var onFinalizeCallback: ((String) -> Void)?
    private let hudPresentationDelay: TimeInterval = 0.2

    private func clearEventMonitors() {
        for monitor in eventMonitors {
            removeEventMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    private func clearKeyUpMonitors() {
        for monitor in keyUpMonitors {
            removeEventMonitor(monitor)
        }
        keyUpMonitors.removeAll()
    }

    private func isHUDRevealedThisSession() -> Bool {
        sessionPhase == .revealed
    }

    private func resetSessionAfterAbortedReveal() {
        sessionPhase = .idle
        currentSelectedAppId = nil
        currentShortcut = nil
        pendingActiveAppId = nil
        stopLooping()
        clearEventMonitors()
        clearKeyUpMonitors()

        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }
    }

    /// Schedule showing the HUD with macOS Command+Tab logic
    func scheduleShow(items: [HUDAppItem], activeAppId: String, modifierFlags: NSEvent.ModifierFlags?, shortcut: String?, activeKey: KeyboardShortcuts.Key? = nil, shouldActivate: Bool = true, immediate: Bool = false, onSelect: ((String) -> Void)? = nil, onFinalize: ((String) -> Void)? = nil) {
        // Cancel existing hide timer
        hideTimer?.invalidate()
        hideTimer = nil // Ensure we don't auto-hide while interacting
        
        // Callbacks are session-scoped. If another shortcut invocation supersedes
        // the current prepared/revealed session, the latest invocation owns the
        // eventual select/finalize callbacks.
        self.onSelectCallback = onSelect
        self.onFinalizeCallback = onFinalize
        
        lastRequestTime = timeProvider.now
        
        // Store pending active app for fast switching
        self.pendingActiveAppId = shouldActivate ? activeAppId : nil
        
        // Store items immediately so fast switch path can look up PID
        self.currentItems = items
        
        if !isSessionActive {
            prepareHUD(items: items, activeAppId: activeAppId, shortcut: shortcut, reveal: false)
            sessionPhase = .preparedInvisible
            startMonitoring(requiredModifiers: modifierFlags, activeKey: activeKey)

            if immediate {
                revealHUD(requiredModifiers: modifierFlags, activeKey: activeKey)
            } else {
                scheduleReveal(requiredModifiers: modifierFlags, activeKey: activeKey)
            }
            return
        }

        prepareHUD(items: items, activeAppId: activeAppId, shortcut: shortcut, reveal: isHUDRevealedThisSession())

        if isHUDRevealedThisSession() {
            startMonitoring(requiredModifiers: modifierFlags, activeKey: activeKey)
            if activeKey != nil {
                scheduleLoopStart()
            }
        } else {
            revealHUD(requiredModifiers: modifierFlags, activeKey: activeKey)
        }
    }

    private func closeVisibleSettingsWindowIfNeeded(beforeActivating appId: String) {
        guard let target = currentItems.first(where: { $0.id == appId || $0.bundleId == appId }) else {
            return
        }
        guard targetLeavesCurrentSpace(target) else {
            return
        }
        guard let settingsWindow = SettingsWindowLifecycleCoordinator.anyVisibleSettingsWindow(
            in: settingsWindowsProvider()
        ) else {
            return
        }

        closeWindow(settingsWindow)
    }
    
    private func prepareHUD(items: [HUDAppItem], activeAppId: String, shortcut: String?, reveal: Bool) {
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

        if reveal {
            setWindowIgnoresMouseEvents(window, false)
            setWindowAlpha(window, 1.0)
        } else {
            setWindowIgnoresMouseEvents(window, true)
            setWindowAlpha(window, 0.0)
        }
        presentHUDWindow(window)
    }

    private func scheduleReveal(requiredModifiers: NSEvent.ModifierFlags?, activeKey: KeyboardShortcuts.Key?) {
        revealTimer?.invalidate()
        revealTimer = timerScheduler.schedule(timeInterval: hudPresentationDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.revealHUD(requiredModifiers: requiredModifiers, activeKey: activeKey)
            }
        }
    }

    private func revealHUD(requiredModifiers: NSEvent.ModifierFlags?, activeKey: KeyboardShortcuts.Key?, shouldStartLoop: Bool? = nil) {
        revealTimer?.invalidate()
        revealTimer = nil

        guard let window else {
            resetSessionAfterAbortedReveal()
            return
        }
        guard sessionPhase != .revealed else {
            if activeKey != nil {
                scheduleLoopStart()
            }
            return
        }

        sessionPhase = .revealed
        setWindowIgnoresMouseEvents(window, false)
        animateWindowAlpha(window, 1.0, 0.12)
        startMonitoring(requiredModifiers: requiredModifiers, activeKey: activeKey)

        let startLoop = shouldStartLoop ?? (activeKey != nil && isLoopKeyHeld)
        if startLoop {
            scheduleLoopStart()
        }
    }
    
    private func scheduleLoopStart() {
        guard isLoopKeyHeld else {
            return
        }

        loopTimer?.invalidate()
        // Wait 0.2s after HUD appears before starting the auto-cycle
        loopTimer = timerScheduler.schedule(timeInterval: 0.2, repeats: false) { [weak self] _ in
             Task { @MainActor in
                 self?.startRepeatingLoop()
             }
         }
    }
    
    // Internal for @testable import access in PressAndHoldTests
    internal var currentLoopKey: Int? // Trace which key is currently driving the loop

    internal var isLoopKeyHeld: Bool = false

    private func startMonitoring(requiredModifiers: NSEvent.ModifierFlags?, activeKey: KeyboardShortcuts.Key? = nil) {
        // Check if we are already looping for this key. If so, DO NOT reset monitors.
        if sessionPhase == .revealed,
           let active = activeKey,
           let current = currentLoopKey,
           active.rawValue == current,
           loopTimer != nil {
            return
        }
        
        // Stop existing monitors
        clearEventMonitors()
        clearKeyUpMonitors()
        loopTimer?.invalidate()
        loopTimer = nil
        isRepeatingLoopActive = false
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
        
        let addFlagsMonitor: (Bool) -> Void = { [weak self] isGlobal in
            guard let self else { return }
            if isGlobal {
                let flagsMonitor = self.addGlobalEventMonitor(.flagsChanged) { [weak self] event in
                    Task { @MainActor in
                        self?.handleFlagsChanged(event: event, required: required)
                    }
                }
                if let flagsMonitor {
                    self.eventMonitors.append(flagsMonitor)
                }
                return
            }

            let flagsMonitor = self.addLocalEventMonitor(.flagsChanged) { [weak self] event in
                Task { @MainActor in
                    self?.handleFlagsChanged(event: event, required: required)
                }
                return event
            }
            if let flagsMonitor {
                self.eventMonitors.append(flagsMonitor)
            }
        }

        addFlagsMonitor(false)
        // ShortcutCycle runs as an accessory app and presents the HUD in a
        // non-activating panel. Keep a global fallback even after reveal because
        // local key delivery is not reliable once focus shifts away from the app.
        addFlagsMonitor(true)

        if sessionPhase == .revealed {
            // Give a tiny grace period for state to settle or for fast release.
            let currentFlags = currentModifierFlags()
            if !checkModifiersHeld(currentFlags: currentFlags, required: required) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self else { return }
                    let flags = self.currentModifierFlags()
                    if self.sessionPhase == .revealed,
                       !self.checkModifiersHeld(currentFlags: flags, required: required) {
                        self.finalizeSwitchAndHide()
                    }
                }
            }
        }
        
        // 2. Loop Logic (Hyper Key / Hold Key)
        if let activeKey = activeKey {
            currentLoopKey = activeKey.rawValue
            isLoopKeyHeld = true

            let handleKeyUp: (NSEvent) -> Void = { [weak self] event in
                guard Int(event.keyCode) == activeKey.rawValue else { return }

                Task { @MainActor in
                    guard let self else { return }
                    self.isLoopKeyHeld = false

                    if let timer = self.revealTimer, timer.isValid {
                        let currentFlags = self.currentModifierFlags()
                        if self.checkModifiersHeld(currentFlags: currentFlags, required: required) {
                            // "Peek" behavior: reveal the HUD immediately, but do not
                            // start auto-cycling because the loop key was released.
                            self.revealHUD(requiredModifiers: requiredModifiers, activeKey: activeKey, shouldStartLoop: false)
                        } else {
                            self.revealTimer?.invalidate()
                            self.revealTimer = nil
                        }
                    }

                    self.stopLooping()
                }
            }

            if let keyMonitor = addGlobalEventMonitor(.keyUp, handleKeyUp) {
                keyUpMonitors.append(keyMonitor)
            }

            if let keyMonitor = addLocalEventMonitor(.keyUp, { event in
                handleKeyUp(event)
                return event
            }) {
                keyUpMonitors.append(keyMonitor)
            }
        }

        guard sessionPhase == .revealed else {
            return
        }

        // Monitor Arrow Keys AND Loop Key for "Heartbeat"
        let keyMonitor = addLocalEventMonitor(.keyDown) { [weak self] event in
            Task { @MainActor in
                // Heartbeat: If this is the active loop key, update the timestamp
                if let active = activeKey, Int(event.keyCode) == active.rawValue {
                    self?.lastLocalKeyDownTime = self?.timeProvider.now
                    return
                }

                // Stop looping if user calculates manually navigation (Arrows, etc)
                // But NOT if it's just the loop key repeating!
                if let active = activeKey, Int(event.keyCode) != active.rawValue {
                    self?.stopLooping()
                } else if activeKey == nil {
                    self?.stopLooping()
                }
            }

            if let active = activeKey, Int(event.keyCode) == active.rawValue {
                return nil // Consume the event so it doesn't beep or do other things
            }

            return self?.handleKeyDown(event: event) ?? event
        }
        if let keyMonitor = keyMonitor {
             eventMonitors.append(keyMonitor)
        }
        
        // Non-activating HUD sessions do not make ShortcutCycle active, so
        // clicking elsewhere usually will not emit didResignActive. Keep this
        // fallback for sessions started while the app is already active, such as
        // from Settings or menu UI.
        appResignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                 self?.hide()
            }
        }
    }
    
    private func startRepeatingLoop() {
        // Don't start if the loop was already cancelled or key was released
        guard currentLoopKey != nil, isLoopKeyHeld else {
            loopTimer?.invalidate()
            loopTimer = nil
            return
        }
        // Hardware double-check: verify key is still physically held
        if let key = currentLoopKey, !CGEventSource.keyState(.hidSystemState, key: CGKeyCode(key)) {
            loopTimer?.invalidate()
            loopTimer = nil
            return
        }
        loopTimer?.invalidate()
        isRepeatingLoopActive = true
        // Repeat every 125ms
        loopTimer = timerScheduler.schedule(timeInterval: 0.125, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.selectNextApp()
            }
        }
    }
    
    private func stopLooping() {
        loopTimer?.invalidate()
        loopTimer = nil
        isRepeatingLoopActive = false
        currentLoopKey = nil // Reset so we accept new requests
        clearKeyUpMonitors()
    }
    
    private func selectNextApp() {
        // If the loop was cancelled (stopLooping cleared currentLoopKey), stop immediately
        guard currentLoopKey != nil else {
            stopLooping()
            return
        }

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
                stopLooping()
                return
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
        
        prepareHUD(items: currentItems, activeAppId: newId, shortcut: nil, reveal: true)
        
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
            prepareHUD(items: currentItems, activeAppId: newId, shortcut: nil, reveal: true)
            self.pendingActiveAppId = newId
            self.onSelectCallback?(newId)
            return nil // Consume event
        }
        
        return event
    }
    
    private func isKeyDown(_ keyCode: Int) -> Bool {
        isKeyCurrentlyDown(keyCode)
    }

    private func areRequiredModifiersPresent(
        in currentFlags: NSEvent.ModifierFlags,
        required: NSEvent.ModifierFlags
    ) -> Bool {
        (!required.contains(.command) || currentFlags.contains(.command))
            && (!required.contains(.option) || currentFlags.contains(.option))
            && (!required.contains(.control) || currentFlags.contains(.control))
            && (!required.contains(.shift) || currentFlags.contains(.shift))
    }

    private func checkModifiersHeld(currentFlags: NSEvent.ModifierFlags, required: NSEvent.ModifierFlags) -> Bool {
        let isModifierHeld: (NSEvent.ModifierFlags, [Int]) -> Bool = { modifier, keyCodes in
            guard required.contains(modifier) else {
                return true
            }

            if keyCodes.contains(where: self.isKeyDown) {
                return true
            }

            // Fallback to flags if the hardware check misses a transient state.
            return currentFlags.contains(modifier)
        }

        return isModifierHeld(.command, [55, 54])
            && isModifierHeld(.option, [58, 61])
            && isModifierHeld(.control, [59, 62])
            && isModifierHeld(.shift, [56, 60])
    }
    
    private func handleFlagsChanged(event: NSEvent, required: NSEvent.ModifierFlags) {
        let currentFlags = event.modifierFlags

        // For an actual flagsChanged event, trust the event payload. Re-querying HID
        // state here can race one tick behind the release event and leave the HUD stuck.
        if !areRequiredModifiersPresent(in: currentFlags, required: required) {
             finalizeSwitchAndHide()
        }
    }
    
    private func fireOnFinalizeIfNeeded() {
        guard let callback = onFinalizeCallback else { return }
        onFinalizeCallback = nil
        if let appId = pendingActiveAppId ?? currentSelectedAppId {
            callback(appId)
        }
    }

    private func finalizeSwitchAndHide() {
        guard sessionPhase != .idle else {
            return
        }

        // Modifiers released
        revealTimer?.invalidate()
        revealTimer = nil

        // KEY CHANGE: Session has ended.
        // Clear the lastRequestTime and lastLocalKeyDownTime tracking so the next interaction is fresh.
        lastRequestTime = nil
        lastLocalKeyDownTime = nil

        stopLooping() // Ensure loop timer and monitor are cleaned up

        fireOnFinalizeIfNeeded()

        // Fast switch: user released keys before HUD appeared or while it was visible
        if let pendingId = pendingActiveAppId {
            if isHUDRevealedThisSession() {
                closeVisibleSettingsWindowIfNeeded(beforeActivating: pendingId)
            }
            activatePendingTargetApp(pendingId)
            pendingActiveAppId = nil
        }
        
        if window != nil || isSessionActive {
            hide() // Hide immediately
            return
        }
        
        // Stop monitoring
        clearEventMonitors()
        clearKeyUpMonitors()
        
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }
    }
    
    private func hasVisibleWindows(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return true
        }
        return list.contains { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
    }

    @discardableResult
    private func advanceActivationAttemptGeneration() -> Int {
        activationAttemptGeneration += 1
        return activationAttemptGeneration
    }

    private func activateRunningTargetApp(_ app: NSRunningApplication) {
        let activationGeneration = advanceActivationAttemptGeneration()
        let didActivate: Bool
        if isAppActive() {
            yieldActivationToRunningApplication(app)
            didActivate = activateRunningApplication(app, true)
        } else {
            didActivate = activateRunningApplication(app, false)
        }

        guard !didActivate else { return }

        logger.warning(
            "Target app activation was declined; retrying bundle=\(app.bundleIdentifier ?? "unknown", privacy: .public) pid=\(app.processIdentifier, privacy: .public)"
        )

        scheduleActivationRetry { [weak self] in
            guard let self,
                  self.activationAttemptGeneration == activationGeneration else {
                return
            }

            self.unhideRunningApplication(app)
            let didRetry = self.activateRunningApplication(app, false)
            guard !didRetry else { return }

            self.logger.error(
                "Target app activation retry failed bundle=\(app.bundleIdentifier ?? "unknown", privacy: .public) pid=\(app.processIdentifier, privacy: .public)"
            )
        }
    }

    private func activateOrLaunch(bundleId: String) {
        // Resolve the real bundle ID from currentItems (bundleId may be a composite "bundleId::pid")
        let item = currentItems.first(where: { $0.id == bundleId || $0.bundleId == bundleId })
        let realBundleId = item?.bundleId ?? bundleId

        if let pid = item?.pid,
           let app = runningApplicationsProvider(realBundleId)
               .first(where: { $0.processIdentifier == pid }) {
            unhideRunningApplication(app)
            // Quick-tap blind switching can happen while ShortcutCycle is still the
            // active app (for example with Settings or menu UI involved). Yield our
            // activation first so the target app can take frontmost focus reliably.
            activateRunningTargetApp(app)
            // If all windows are minimized, activate() succeeds but nothing appears on screen.
            // After a short delay, check via CGWindowList (no Accessibility permission needed);
            // if no visible windows exist, re-activate the specific instance to ensure it is
            // frontmost, then call openApplication so that instance receives
            // applicationShouldHandleReopen and restores its minimized windows.
            scheduleVisibleWindowRecheck { [weak self] in
                guard let self else { return }
                guard !self.hasVisibleWindowsForPID(pid) else { return }
                self.activateRunningTargetApp(app)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.launchApp(bundleIdentifier: realBundleId)
                }
            }
            return
        }
        advanceActivationAttemptGeneration()
        launchApp(bundleIdentifier: realBundleId)
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

    #if DEBUG
    func presentScreenshotHUD(items: [HUDAppItem], activeAppId: String, shortcut: String?) -> NSWindow? {
        resetForScreenshotPresentation()
        prepareHUD(items: items, activeAppId: activeAppId, shortcut: shortcut, reveal: true)
        sessionPhase = .revealed
        window?.sharingType = .readOnly
        return window
    }

    private func resetForScreenshotPresentation() {
        hideTimer?.invalidate()
        hideTimer = nil
        revealTimer?.invalidate()
        revealTimer = nil
        loopTimer?.invalidate()
        loopTimer = nil

        clearEventMonitors()
        clearKeyUpMonitors()

        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }

        lastRequestTime = nil
        lastLocalKeyDownTime = nil
        isRepeatingLoopActive = false
        currentLoopKey = nil
        isLoopKeyHeld = false
        pendingActiveAppId = nil
        onSelectCallback = nil
        onFinalizeCallback = nil
    }
    #endif
    
    /// Hide the HUD
    func hide() {
        guard sessionPhase != .idle
            || window != nil
            || currentSelectedAppId != nil
            || currentShortcut != nil
            || pendingActiveAppId != nil
            || hideTimer != nil
            || revealTimer != nil
            || loopTimer != nil
            || currentLoopKey != nil
            || isLoopKeyHeld
            || isRepeatingLoopActive
            || lastRequestTime != nil
            || lastLocalKeyDownTime != nil
            || !eventMonitors.isEmpty
            || !keyUpMonitors.isEmpty
            || appResignObserver != nil
        else {
            return
        }

        fireOnFinalizeIfNeeded()
        let hadRevealedHUD = isHUDRevealedThisSession()
        window?.orderOut(nil)
        window = nil
        currentSelectedAppId = nil
        currentShortcut = nil
        sessionPhase = .idle

        // Ensure we activate the pending app if it exists (fallback)
        if let pendingId = pendingActiveAppId {
            if hadRevealedHUD {
                closeVisibleSettingsWindowIfNeeded(beforeActivating: pendingId)
            }
            activatePendingTargetApp(pendingId)
            pendingActiveAppId = nil
        }
        
        // Activating the target app is enough to yield focus back. Hiding the
        // menu-bar app itself can leave the status item visible but non-interactive.

        hideTimer?.invalidate()
        hideTimer = nil
        revealTimer?.invalidate()
        revealTimer = nil
        lastLocalKeyDownTime = nil
        lastRequestTime = nil
        stopLooping()
        
        clearEventMonitors()
        clearKeyUpMonitors()
        
        if let observer = appResignObserver {
            NotificationCenter.default.removeObserver(observer)
            appResignObserver = nil
        }
    }
}

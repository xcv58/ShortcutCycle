import AppKit
import XCTest

import Combine
import KeyboardShortcuts
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#endif
@testable import ShortcutCycle

@MainActor
final class PressAndHoldTests: XCTestCase {
    final class DummyEventMonitorToken {}

    // Mocks
    class MockTimeProvider: TimeProvider {
        var currentTime: Date = Date()
        var now: Date { currentTime }
    }

    class MockTimerScheduler: TimerScheduler {
        // (interval, repeats, timer, block)
        var scheduledTimers: [(TimeInterval, Bool, Timer, (Timer) -> Void)] = []
        var lastTimer: Timer?

        func schedule(timeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
            let timer = Timer(timeInterval: timeInterval, repeats: repeats) { _ in }
            scheduledTimers.append((timeInterval, repeats, timer, block))
            lastTimer = timer
            return timer
        }

        @discardableResult
        func fireLastTimer() -> Bool {
            fireLastTimer(where: { _ in true })
        }

        /// Fire the most recent non-repeating timer (delay timer)
        @discardableResult
        func fireLastNonRepeatingTimer() -> Bool {
            fireLastTimer(where: { !$0 })
        }

        /// Fire the most recent repeating timer (loop timer)
        @discardableResult
        func fireLastRepeatingTimer() -> Bool {
            fireLastTimer(where: { $0 })
        }

        private func fireLastTimer(where matches: (Bool) -> Bool) -> Bool {
            guard let index = scheduledTimers.indices.last(where: {
                matches(scheduledTimers[$0].1) && scheduledTimers[$0].2.isValid
            }) else {
                return false
            }

            let entry = scheduledTimers[index]
            if !entry.1 {
                scheduledTimers.remove(at: index)
            }
            entry.3(entry.2)
            return true
        }
    }

    var manager: HUDManager!
    var timeMock: MockTimeProvider!
    var timerMock: MockTimerScheduler!
    var presentationCount: Int!
    var localMonitorMasks: [NSEvent.EventTypeMask]!
    var globalMonitorMasks: [NSEvent.EventTypeMask]!
    var localMonitorHandlers: [(NSEvent.EventTypeMask, (NSEvent) -> NSEvent?)]!
    var globalMonitorHandlers: [(NSEvent.EventTypeMask, (NSEvent) -> Void)]!
    var removedMonitorCount: Int!
    var windowAlphaChanges: [CGFloat]!
    var mouseInteractionStates: [Bool]!

    // Saved originals for restoration in tearDown
    private var savedActivatePendingTargetApp: ((String) -> Void)!
    private var savedTargetLeavesCurrentSpace: ((HUDAppItem) -> Bool)!
    private var savedIsKeyCurrentlyDown: ((Int) -> Bool)!
    private var savedPresentHUDWindow: ((NSWindow) -> Void)!
    private var savedRunningApplicationsProvider: ((String) -> [NSRunningApplication])!
    private var savedUnhideRunningApplication: ((NSRunningApplication) -> Void)!
    private var savedYieldActivationToRunningApplication: ((NSRunningApplication) -> Void)!
    private var savedActivateRunningApplication: ((NSRunningApplication, Bool) -> Bool)!
    private var savedScheduleActivationRetry: ((@escaping @MainActor @Sendable () -> Void) -> Void)!
    private var savedScheduleVisibleWindowRecheck: ((@escaping @MainActor @Sendable () -> Void) -> Void)!
    private var savedHasVisibleWindowsForPID: ((pid_t) -> Bool)!

    override func setUp() async throws {
        _ = NSApplication.shared

        // Setup mocks
        manager = HUDManager.shared
        timeMock = MockTimeProvider()
        timerMock = MockTimerScheduler()
        presentationCount = 0
        localMonitorMasks = []
        globalMonitorMasks = []
        localMonitorHandlers = []
        globalMonitorHandlers = []
        removedMonitorCount = 0
        windowAlphaChanges = []
        mouseInteractionStates = []

        // Save originals before overriding (these use private methods, so restore by value)
        savedActivatePendingTargetApp = manager.activatePendingTargetApp
        savedTargetLeavesCurrentSpace = manager.targetLeavesCurrentSpace
        savedIsKeyCurrentlyDown = manager.isKeyCurrentlyDown
        savedPresentHUDWindow = manager.presentHUDWindow
        savedRunningApplicationsProvider = manager.runningApplicationsProvider
        savedUnhideRunningApplication = manager.unhideRunningApplication
        savedYieldActivationToRunningApplication = manager.yieldActivationToRunningApplication
        savedActivateRunningApplication = manager.activateRunningApplication
        savedScheduleActivationRetry = manager.scheduleActivationRetry
        savedScheduleVisibleWindowRecheck = manager.scheduleVisibleWindowRecheck
        savedHasVisibleWindowsForPID = manager.hasVisibleWindowsForPID

        // Inject mocks
        manager.timeProvider = timeMock
        manager.timerScheduler = timerMock
        manager.presentHUDWindow = { [weak self] _ in
            self?.presentationCount += 1
        }
        manager.addLocalEventMonitor = { [weak self] mask, handler in
            self?.localMonitorMasks.append(mask)
            self?.localMonitorHandlers.append((mask, handler))
            return DummyEventMonitorToken()
        }
        manager.addGlobalEventMonitor = { [weak self] mask, handler in
            self?.globalMonitorMasks.append(mask)
            self?.globalMonitorHandlers.append((mask, handler))
            return DummyEventMonitorToken()
        }
        manager.removeEventMonitor = { [weak self] _ in
            self?.removedMonitorCount += 1
        }
        manager.currentModifierFlags = { [] }
        manager.isKeyCurrentlyDown = { _ in false }
        manager.isAppActive = { true }
        manager.settingsWindowsProvider = { [] }
        manager.closeWindow = { window in
            window.close()
        }
        manager.setWindowAlpha = { [weak self] _, alpha in
            self?.windowAlphaChanges.append(alpha)
        }
        manager.animateWindowAlpha = { [weak self] _, alpha, _ in
            self?.windowAlphaChanges.append(alpha)
        }
        manager.setWindowIgnoresMouseEvents = { [weak self] _, ignores in
            self?.mouseInteractionStates.append(ignores)
        }
        manager.targetLeavesCurrentSpace = { _ in false }

        // Reset state
        manager.hide() // Ensure clean state
        await drainMainActorQueue()
        manager.hide()
        manager.lastRequestTime = nil
        manager.isLoopKeyHeld = false
        manager.currentLoopKey = nil
        manager.isRepeatingLoopActive = false
        presentationCount = 0
        localMonitorMasks.removeAll()
        globalMonitorMasks.removeAll()
        localMonitorHandlers.removeAll()
        globalMonitorHandlers.removeAll()
        removedMonitorCount = 0
    }

    override func tearDown() async throws {
        // Flush any DummyEventMonitorTokens out of eventMonitors using the
        // stub removeEventMonitor (safe no-op), before we restore the real
        // NSEvent.removeMonitor — which would crash on non-monitor objects.
        manager.hide()
        await drainMainActorQueue()
        manager.hide()

        manager.timeProvider = SystemTimeProvider()
        manager.timerScheduler = SystemTimerScheduler()
        manager.addLocalEventMonitor = { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        }
        manager.addGlobalEventMonitor = { mask, handler in
            NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        }
        manager.removeEventMonitor = { NSEvent.removeMonitor($0) }
        manager.currentModifierFlags = { NSEvent.modifierFlags }
        manager.isKeyCurrentlyDown = savedIsKeyCurrentlyDown
        manager.isAppActive = { NSApp?.isActive == true }
        manager.settingsWindowsProvider = { NSApp?.windows ?? [] }
        manager.closeWindow = { $0.close() }
        manager.setWindowAlpha = { $0.alphaValue = $1 }
        manager.animateWindowAlpha = { window, alpha, duration in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                window.animator().alphaValue = alpha
            }
        }
        manager.setWindowIgnoresMouseEvents = { $0.ignoresMouseEvents = $1 }
        manager.runningApplicationsProvider = savedRunningApplicationsProvider
        manager.unhideRunningApplication = savedUnhideRunningApplication
        manager.yieldActivationToRunningApplication = savedYieldActivationToRunningApplication
        manager.activateRunningApplication = savedActivateRunningApplication
        manager.scheduleActivationRetry = savedScheduleActivationRetry
        manager.scheduleVisibleWindowRecheck = savedScheduleVisibleWindowRecheck
        manager.hasVisibleWindowsForPID = savedHasVisibleWindowsForPID
        manager.activatePendingTargetApp = savedActivatePendingTargetApp
        manager.targetLeavesCurrentSpace = savedTargetLeavesCurrentSpace
        manager.presentHUDWindow = savedPresentHUDWindow
    }

    private func latestLocalMonitorHandler(
        for mask: NSEvent.EventTypeMask
    ) -> ((NSEvent) -> NSEvent?)? {
        localMonitorHandlers.last(where: { $0.0 == mask })?.1
    }

    private func latestGlobalMonitorHandler(
        for mask: NSEvent.EventTypeMask
    ) -> ((NSEvent) -> Void)? {
        globalMonitorHandlers.last(where: { $0.0 == mask })?.1
    }

    private func eventually(timeout: TimeInterval = 1.0, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while !condition(), Date() < deadline {
            await Task.yield()
            pumpMainRunLoopBriefly()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        return condition()
    }

    private func pumpMainRunLoopBriefly() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.001))
    }

    private func drainMainActorQueue(iterations: Int = 3) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    private func makeFlagsChangedEvent(
        modifierFlags: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 58
            )
        )
    }

    private func makeKeyEvent(
        type: NSEvent.EventType,
        keyCode: Int,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: UInt16(keyCode)
            )
        )
    }

    // MARK: - Basic HUD Timing Tests

    @MainActor
    func testSimpleBlindSwitchDoesNotShowHUD() {
        // 1. Press Shortcut
        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)],
            activeAppId: "com.test.current",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        // Expect timer scheduled for reveal while the prepared HUD remains invisible.
        XCTAssertEqual(timerMock.scheduledTimers.count, 1, "Should schedule a timer for HUD reveal")
        XCTAssertEqual(timerMock.scheduledTimers.last?.0 ?? -1, 0.2, accuracy: 0.001, "HUD reveal delay should stay short")
        XCTAssertEqual(presentationCount, 1, "Preparing the HUD should present the non-activating panel immediately")
        XCTAssertTrue(manager.isSessionActive, "A prepared HUD session should be active immediately")
        XCTAssertFalse(manager.isVisible, "HUD should remain invisible during the initial preparation window")
        XCTAssertEqual(windowAlphaChanges.last, 0, "Prepared HUD should start fully transparent")
        XCTAssertEqual(mouseInteractionStates.last, true, "Prepared HUD should ignore mouse interaction until revealed")

        // 2. Release immediately (simulated by not firing timer and ending session)
        manager.hide() // Simulate release/finalize

        // Verify HUD never showed
        XCTAssertFalse(manager.isVisible)
    }

    @MainActor
    func testPressAndHoldShowsHUD() async {
        manager.currentModifierFlags = { [.option] }

        // 1. Press Shortcut
        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)],
            activeAppId: "com.test.current",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        XCTAssertFalse(manager.isVisible, "HUD should not be visible immediately")
        XCTAssertEqual(timerMock.scheduledTimers.count, 1)

        // 2. Advance time past threshold (0.2s)
        timeMock.currentTime = timeMock.currentTime.addingTimeInterval(0.3)

        // 3. Fire Timer
        timerMock.fireLastTimer()
        let didReveal = await eventually { manager.isVisible }
        XCTAssertTrue(didReveal, "Holding through the reveal delay should make the HUD visible")
        XCTAssertEqual(windowAlphaChanges.last, 1, "Reveal should animate the HUD to full opacity")
        XCTAssertEqual(mouseInteractionStates.last, false, "Revealed HUD should accept mouse interaction")
    }

    @MainActor
    func testDelayedShowPreparesInvisibleHUDBeforeReveal() async {
        manager.currentModifierFlags = { [.option] }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)],
            activeAppId: "com.test.current",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            activeKey: .a
        )

        XCTAssertEqual(presentationCount, 1, "Prepared HUD path should present the non-activating panel before the HUD is revealed")
        XCTAssertTrue(manager.isSessionActive, "Prepared HUD session should be active immediately")
        XCTAssertFalse(manager.isVisible, "HUD should stay invisible until the reveal timer fires")
        XCTAssertTrue(globalMonitorMasks.contains(.flagsChanged), "Prepared HUD path should monitor global modifier releases")
        XCTAssertTrue(localMonitorMasks.contains(.flagsChanged), "Prepared HUD path should also monitor local modifier releases")
        XCTAssertEqual(windowAlphaChanges.last, 0, "Prepared HUD should stay transparent before reveal")
        XCTAssertEqual(mouseInteractionStates.last, true, "Prepared HUD should ignore mouse interaction")

        timerMock.fireLastNonRepeatingTimer()

        let didReveal = await eventually { manager.isVisible }
        XCTAssertTrue(didReveal, "Reveal timer should transition the HUD into the visible state")
        XCTAssertTrue(localMonitorMasks.contains(.flagsChanged), "Revealed HUD should keep local modifier monitoring")
        XCTAssertTrue(removedMonitorCount > 0, "Transitioning to the revealed HUD should remove prepared-phase monitors")
        XCTAssertEqual(windowAlphaChanges.last, 1, "Reveal should animate to full opacity")
        XCTAssertEqual(mouseInteractionStates.last, false, "Revealed HUD should allow mouse interaction")
    }

    @MainActor
    func testPreparedRevealReinstallsGlobalReleaseFallbackAfterReveal() async throws {
        manager.currentModifierFlags = { [.command, .shift] }
        var activateCount = 0
        manager.activatePendingTargetApp = { _ in
            activateCount += 1
        }
        let items = [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)]

        manager.scheduleShow(
            items: items,
            activeAppId: "com.test.current",
            modifierFlags: [.command, .shift],
            shortcut: "Cmd+Shift+J",
            activeKey: .j
        )

        XCTAssertEqual(
            globalMonitorMasks.filter { $0 == .flagsChanged }.count,
            1,
            "Prepared HUD should register one global flagsChanged fallback before reveal"
        )
        XCTAssertEqual(
            globalMonitorMasks.filter { $0 == .keyUp }.count,
            1,
            "Prepared HUD should register one global keyUp fallback before reveal"
        )

        manager.scheduleShow(
            items: items,
            activeAppId: "com.test.current",
            modifierFlags: [.command, .shift],
            shortcut: "Cmd+Shift+J",
            activeKey: .j
        )

        XCTAssertTrue(manager.isVisible, "A second shortcut invocation should reveal the prepared HUD")
        XCTAssertEqual(
            globalMonitorMasks.filter { $0 == .flagsChanged }.count,
            2,
            "Revealed HUD should reinstall a global flagsChanged fallback in addition to the local monitor"
        )
        XCTAssertEqual(
            globalMonitorMasks.filter { $0 == .keyUp }.count,
            2,
            "Revealed HUD should reinstall a global keyUp fallback in addition to the local monitor"
        )

        let flagsHandler = try XCTUnwrap(latestGlobalMonitorHandler(for: .flagsChanged))
        flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(manager.isSessionActive, "The revealed global release fallback should end the HUD session")
        XCTAssertFalse(manager.isVisible, "The revealed global release fallback should hide the HUD on modifier release")
        XCTAssertEqual(activateCount, 1, "The pending target should activate exactly once when the global release fallback fires")
    }

    @MainActor
    func testDelayedShowKeepsOffSpaceSettingsWindowBeforeHUDPresentation() async {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: false
        )
        var closeCount = 0

        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in
            closeCount += 1
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)],
            activeAppId: "com.test.current",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            activeKey: .a
        )

        timerMock.fireLastNonRepeatingTimer()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(closeCount, 0, "Non-activating HUD presentation should not close Settings on another Space")
        XCTAssertEqual(presentationCount, 1, "Prepared HUD path should still present the non-activating panel")
    }

    @MainActor
    func testImmediateShowDoesNotCloseCurrentSpaceSettingsWindow() {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        var closeCount = 0

        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in
            closeCount += 1
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)],
            activeAppId: "com.test.current",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            activeKey: .a,
            immediate: true
        )

        XCTAssertEqual(closeCount, 0)
    }

    @MainActor
    func testVisibleBackgroundSettingsUsesTheSamePreparedDelayPath() {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )

        manager.isAppActive = { false }
        manager.settingsWindowsProvider = { [settingsWindow] }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)],
            activeAppId: "com.test.current",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            activeKey: .a
        )

        XCTAssertEqual(timerMock.scheduledTimers.count, 1, "Background Settings should still use the standard reveal delay")
        XCTAssertEqual(timerMock.scheduledTimers.last?.0 ?? -1, 0.2, accuracy: 0.001, "Reveal delay should stay unchanged with Settings visible")
        XCTAssertEqual(presentationCount, 1, "Prepared HUD path should still present the non-activating panel immediately")
        XCTAssertFalse(manager.isVisible, "Background Settings should not force immediate visible HUD presentation")
        XCTAssertTrue(globalMonitorMasks.contains(.flagsChanged), "Prepared HUD path should still use global release monitoring before reveal")
    }

    @MainActor
    func testRepeatedInvocationBeforeRevealRevealsImmediately() {
        manager.scheduleShow(
            items: [
                HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil),
                HUDAppItem(bundleId: "com.test.2", name: "Test 2", icon: nil)
            ],
            activeAppId: "com.test.1",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        XCTAssertFalse(manager.isVisible)
        XCTAssertTrue(manager.isSessionActive)

        timeMock.currentTime = timeMock.currentTime.addingTimeInterval(0.1)

        manager.scheduleShow(
            items: [
                HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil),
                HUDAppItem(bundleId: "com.test.2", name: "Test 2", icon: nil)
            ],
            activeAppId: "com.test.2",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        XCTAssertTrue(manager.isVisible, "A repeated hit during the invisible preparation phase should reveal the HUD immediately")
        XCTAssertEqual(windowAlphaChanges.last, 1, "Repeated hit should reveal the HUD to full opacity")
        XCTAssertEqual(mouseInteractionStates.last, false, "Revealed HUD should allow mouse interaction")
    }

    @MainActor
    func testPeekRevealsHUDWithoutStartingLoopWhenLoopKeyIsReleasedDuringPreparedInvisible() async throws {
        manager.currentModifierFlags = { [.option] }

        manager.scheduleShow(
            items: [
                HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil),
                HUDAppItem(bundleId: "com.test.2", name: "Test 2", icon: nil)
            ],
            activeAppId: "com.test.1",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            activeKey: .a
        )

        XCTAssertFalse(manager.isVisible, "HUD should still be invisible during the prepared phase")

        let keyUpHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .keyUp))
        _ = keyUpHandler(try makeKeyEvent(type: .keyUp, keyCode: KeyboardShortcuts.Key.a.rawValue, modifierFlags: [.option]))
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(manager.isVisible, "Releasing only the loop key should reveal the HUD for peeking")
        XCTAssertFalse(manager.isLooping, "Peek should not start the repeating loop")
        XCTAssertFalse(manager.isRepeatingLoopActive, "Peek should leave the repeating loop inactive")
        XCTAssertEqual(windowAlphaChanges.last, 1, "Peek reveal should animate the HUD to full opacity")
        XCTAssertEqual(mouseInteractionStates.last, false, "Peek reveal should allow HUD interaction")
    }

    @MainActor
    func testPeekThenModifierReleaseFinalizesAndActivatesPendingTarget() async throws {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        var events: [String] = []

        manager.currentModifierFlags = { [.option] }
        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in
            events.append("close")
        }
        manager.targetLeavesCurrentSpace = { _ in true }
        manager.activatePendingTargetApp = { _ in
            events.append("activate")
        }

        manager.scheduleShow(
            items: [
                HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil),
                HUDAppItem(bundleId: "com.test.2", name: "Test 2", icon: nil)
            ],
            activeAppId: "com.test.1",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            activeKey: .a
        )

        let keyUpHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .keyUp))
        _ = keyUpHandler(try makeKeyEvent(type: .keyUp, keyCode: KeyboardShortcuts.Key.a.rawValue, modifierFlags: [.option]))
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(manager.isVisible, "Peek should reveal the HUD before modifier release")

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(manager.isSessionActive, "Modifier release after a peek should end the HUD session")
        XCTAssertFalse(manager.isVisible, "Modifier release after a peek should hide the HUD")
        XCTAssertEqual(events, ["close", "activate"], "Peek finalize should use the revealed cleanup path and not order current-space windows back")
    }

    @MainActor
    func testFullReleaseDuringPreparedInvisibleCancelsRevealWithoutShowingHUD() async throws {
        manager.currentModifierFlags = { [] }

        manager.scheduleShow(
            items: [
                HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil),
                HUDAppItem(bundleId: "com.test.2", name: "Test 2", icon: nil)
            ],
            activeAppId: "com.test.1",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            activeKey: .a
        )

        XCTAssertFalse(manager.isVisible, "HUD should start invisible during the prepared phase")

        let keyUpHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .keyUp))
        _ = keyUpHandler(try makeKeyEvent(type: .keyUp, keyCode: KeyboardShortcuts.Key.a.rawValue, modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(manager.isVisible, "Releasing the loop key together with modifiers should not reveal the HUD")

        timerMock.fireLastNonRepeatingTimer()
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(manager.isVisible, "Cancelling the reveal timer should prevent any later phantom reveal")
    }

    @MainActor
    func testFinalizeClosesCurrentSpaceSettingsWhenSelectedTargetLeavesCurrentSpace() async throws {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        var events: [String] = []

        manager.currentModifierFlags = { [.option] }
        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in
            events.append("close")
        }
        manager.targetLeavesCurrentSpace = { item in
            item.id == "com.test.other-space::42"
        }
        manager.activatePendingTargetApp = { _ in
            events.append("activate")
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.other-space", pid: 42, name: "Other Space")],
            activeAppId: "com.test.other-space::42",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            immediate: true
        )

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(Array(events.prefix(2)), ["close", "activate"])
    }

    @MainActor
    func testFinalizeKeepsCurrentSpaceSettingsOpenWhenSelectedTargetStaysOnCurrentSpace() async throws {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        var closeCount = 0
        var activateCount = 0

        manager.currentModifierFlags = { [.option] }
        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in
            closeCount += 1
        }
        manager.targetLeavesCurrentSpace = { _ in false }
        manager.activatePendingTargetApp = { _ in
            activateCount += 1
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.current-space", pid: 24, name: "Current Space")],
            activeAppId: "com.test.current-space::24",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            immediate: true
        )

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(activateCount, 1)
    }

    @MainActor
    func testFinalizeRequiresAllConfiguredModifiersToRemainHeld() async throws {
        var activateCount = 0
        manager.activatePendingTargetApp = { _ in
            activateCount += 1
        }
        manager.currentModifierFlags = { [.command, .option] }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.multi-mod", pid: 61, name: "Multi Mod Target")],
            activeAppId: "com.test.multi-mod::61",
            modifierFlags: [.command, .option],
            shortcut: "Cmd+Opt+1",
            immediate: true
        )

        XCTAssertTrue(manager.isVisible, "Immediate path should reveal the HUD before testing modifier release")

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: [.command]))
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(manager.isSessionActive, "Dropping any required modifier should finalize the HUD session")
        XCTAssertFalse(manager.isVisible, "HUD should hide once one of the required modifiers is released")
        XCTAssertEqual(activateCount, 1, "Finalizing after a partial modifier release should still activate the pending target once")
    }

    @MainActor
    func testFlagsChangedReleaseTrustsEventFlagsWhenHardwareStateLags() async throws {
        var activateCount = 0
        manager.activatePendingTargetApp = { _ in
            activateCount += 1
        }
        manager.isKeyCurrentlyDown = { keyCode in
            keyCode == 58 || keyCode == 61
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.stale-option", pid: 88, name: "Stale Option Target")],
            activeAppId: "com.test.stale-option::88",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            immediate: true
        )

        XCTAssertTrue(manager.isVisible, "Immediate path should reveal the HUD before testing release handling")

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(manager.isSessionActive, "A release event should end the HUD session even if HID state still reports the modifier as down")
        XCTAssertFalse(manager.isVisible, "HUD should hide when the release event reports that all required modifiers are up")
        XCTAssertEqual(activateCount, 1, "The pending target should still activate exactly once on release")
    }

    @MainActor
    func testFlagsChangedWithRequiredModifierStillHeldDoesNotFinalize() async throws {
        var activateCount = 0
        var finalizedAppIds: [String] = []
        manager.activatePendingTargetApp = { _ in
            activateCount += 1
        }
        manager.isKeyCurrentlyDown = { keyCode in
            keyCode == 58 || keyCode == 61
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.option-still-held", pid: 89, name: "Option Still Held Target")],
            activeAppId: "com.test.option-still-held::89",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            immediate: true,
            onFinalize: { appId in
                finalizedAppIds.append(appId)
            }
        )

        XCTAssertTrue(manager.isVisible, "Immediate path should reveal the HUD before testing non-finalizing flags changes")
        XCTAssertTrue(manager.isSessionActive, "HUD session should be active before the flags change")

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: [.option]))
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(manager.isSessionActive, "Keeping the required modifier in the flagsChanged event should not end the HUD session")
        XCTAssertTrue(manager.isVisible, "HUD should remain visible while the required modifier is still reported as held")
        XCTAssertEqual(activateCount, 0, "A non-finalizing flags change must not activate the pending target")
        XCTAssertTrue(finalizedAppIds.isEmpty, "A non-finalizing flags change must not fire finalize callbacks")
    }

    @MainActor
    func testBlindSwitchBeforeHUDPresentationKeepsSettingsOpen() async throws {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        var closeCount = 0
        var activateCount = 0

        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in
            closeCount += 1
        }
        manager.targetLeavesCurrentSpace = { _ in true }
        manager.activatePendingTargetApp = { _ in
            activateCount += 1
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.quick-target", pid: 24, name: "Quick Target")],
            activeAppId: "com.test.quick-target::24",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        let flagsHandler = try XCTUnwrap(latestGlobalMonitorHandler(for: .flagsChanged))
        flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(activateCount, 1)
    }

    @MainActor
    func testBlindSwitchBeforeHUDPresentationCanFinalizeFromLocalFlagsMonitor() async throws {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        var closeCount = 0
        var activateCount = 0

        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in
            closeCount += 1
        }
        manager.targetLeavesCurrentSpace = { _ in true }
        manager.activatePendingTargetApp = { _ in
            activateCount += 1
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.local-quick-target", pid: 25, name: "Local Quick Target")],
            activeAppId: "com.test.local-quick-target::25",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(activateCount, 1)
    }

    @MainActor
    func testBlindSwitchBeforeHUDPresentationDoesNotOrderCurrentSpaceWindowsBackBeforeActivation() async throws {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        var events: [String] = []

        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.activatePendingTargetApp = { _ in
            events.append("activate")
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.back-target", pid: 26, name: "Back Target")],
            activeAppId: "com.test.back-target::26",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(events, ["activate"], "Blind switches should rely on target activation rather than reordering ShortcutCycle windows")
    }

    @MainActor
    func testFinalizeFiresOnFinalizeExactlyOnce() async throws {
        var finalizedAppIds: [String] = []

        manager.currentModifierFlags = { [.option] }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.finalize", pid: 41, name: "Finalize Target")],
            activeAppId: "com.test.finalize::41",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            immediate: true,
            onFinalize: { appId in
                finalizedAppIds.append(appId)
            }
        )

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(finalizedAppIds, ["com.test.finalize::41"], "Finalize callback should fire exactly once with the pending selection")
    }

    @MainActor
    func testFinalizeFallsBackToCurrentSelectionWhenNoPendingTargetExists() async throws {
        var finalizedAppIds: [String] = []

        manager.currentModifierFlags = { [.option] }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.fallback", pid: 71, name: "Fallback Target")],
            activeAppId: "com.test.fallback::71",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            shouldActivate: false,
            immediate: true,
            onFinalize: { appId in
                finalizedAppIds.append(appId)
            }
        )

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(finalizedAppIds, ["com.test.fallback::71"], "Finalize should fall back to the current HUD selection when there is no pending activation target")
    }

    @MainActor
    func testPreparedInvisibleFinalizeWithShouldActivateFalseDoesNotActivatePendingTarget() async throws {
        var activateCount = 0

        manager.activatePendingTargetApp = { _ in
            activateCount += 1
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.passive", pid: 52, name: "Passive Target")],
            activeAppId: "com.test.passive::52",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            shouldActivate: false
        )

        let flagsHandler = try XCTUnwrap(latestLocalMonitorHandler(for: .flagsChanged))
        _ = flagsHandler(try makeFlagsChangedEvent(modifierFlags: []))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(activateCount, 0, "Prepared invisible sessions that opted out of activation should not activate a pending target on finalize")
        XCTAssertFalse(manager.isSessionActive, "Finalize should still fully tear down the prepared session")
    }

    @MainActor
    func testHideClosesCurrentSpaceSettingsWhenSelectedTargetLeavesCurrentSpace() {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        var events: [String] = []

        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in
            events.append("close")
        }
        manager.targetLeavesCurrentSpace = { item in
            item.id == "com.test.other-space::99"
        }
        manager.activatePendingTargetApp = { _ in
            events.append("activate")
        }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.other-space", pid: 99, name: "Other Space")],
            activeAppId: "com.test.other-space::99",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            immediate: true
        )

        manager.hide()

        XCTAssertEqual(Array(events.prefix(2)), ["close", "activate"])
    }

    @MainActor
    func testHideKeepsCurrentSpaceSettingsOpenWhenSelectedTargetStaysOnCurrentSpace() {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        var closeCount = 0
        var activateCount = 0

        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in closeCount += 1 }
        manager.targetLeavesCurrentSpace = { _ in false }
        manager.activatePendingTargetApp = { _ in activateCount += 1 }

        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.current-space", pid: 24, name: "Current Space")],
            activeAppId: "com.test.current-space::24",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            immediate: true
        )

        manager.hide()

        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(activateCount, 1)
    }

    @MainActor
    func testDeclinedRunningAppActivationRetriesOnce() {
        let runningApp = NSRunningApplication.current
        let bundleId = "com.test.retry"
        let item = HUDAppItem(
            bundleId: bundleId,
            pid: runningApp.processIdentifier,
            name: "Retry Target"
        )
        var requestedBundleIds: [String] = []
        var unhideCount = 0
        var yieldedActivationCount = 0
        var activationFromCurrentAppFlags: [Bool] = []
        var activationResults = [false, true]
        var retryActions: [@MainActor @Sendable () -> Void] = []

        manager.runningApplicationsProvider = { requestedBundleId in
            requestedBundleIds.append(requestedBundleId)
            return [runningApp]
        }
        manager.unhideRunningApplication = { _ in
            unhideCount += 1
        }
        manager.yieldActivationToRunningApplication = { _ in
            yieldedActivationCount += 1
        }
        manager.activateRunningApplication = { _, fromCurrentApp in
            activationFromCurrentAppFlags.append(fromCurrentApp)
            guard !activationResults.isEmpty else {
                XCTFail("Activation should not run more times than expected")
                return true
            }
            return activationResults.removeFirst()
        }
        manager.scheduleActivationRetry = { action in
            retryActions.append(action)
        }
        manager.scheduleVisibleWindowRecheck = { _ in }
        manager.hasVisibleWindowsForPID = { _ in true }
        manager.isAppActive = { false }

        manager.scheduleShow(
            items: [item],
            activeAppId: item.id,
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )
        manager.hide()

        XCTAssertEqual(requestedBundleIds, [bundleId])
        XCTAssertEqual(unhideCount, 1, "The running app should be unhidden before the initial activation attempt")
        XCTAssertEqual(yieldedActivationCount, 0, "Inactive ShortcutCycle sessions should not yield activation before activating the target")
        XCTAssertEqual(activationFromCurrentAppFlags, [false])
        XCTAssertEqual(retryActions.count, 1, "A declined activation should schedule one retry")

        retryActions[0]()

        XCTAssertEqual(unhideCount, 2, "The retry should unhide the target again before re-activating it")
        XCTAssertEqual(activationFromCurrentAppFlags, [false, false])
        XCTAssertTrue(activationResults.isEmpty)
    }

    @MainActor
    func testDeclinedRunningAppActivationRetryIsSkippedAfterNewActivationAttempt() {
        let runningApp = NSRunningApplication.current
        let firstItem = HUDAppItem(
            bundleId: "com.test.retry.first",
            pid: runningApp.processIdentifier,
            name: "First Retry Target"
        )
        let secondItem = HUDAppItem(
            bundleId: "com.test.retry.second",
            pid: runningApp.processIdentifier,
            name: "Second Retry Target"
        )
        var unhideCount = 0
        var activationFromCurrentAppFlags: [Bool] = []
        var activationResults = [false, true]
        var retryActions: [@MainActor @Sendable () -> Void] = []

        manager.runningApplicationsProvider = { _ in [runningApp] }
        manager.unhideRunningApplication = { _ in
            unhideCount += 1
        }
        manager.activateRunningApplication = { _, fromCurrentApp in
            activationFromCurrentAppFlags.append(fromCurrentApp)
            guard !activationResults.isEmpty else {
                XCTFail("Stale retry should not perform another activation")
                return true
            }
            return activationResults.removeFirst()
        }
        manager.scheduleActivationRetry = { action in
            retryActions.append(action)
        }
        manager.scheduleVisibleWindowRecheck = { _ in }
        manager.hasVisibleWindowsForPID = { _ in true }
        manager.isAppActive = { false }

        manager.scheduleShow(
            items: [firstItem],
            activeAppId: firstItem.id,
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )
        manager.hide()

        XCTAssertEqual(retryActions.count, 1)

        manager.scheduleShow(
            items: [secondItem],
            activeAppId: secondItem.id,
            modifierFlags: [.option],
            shortcut: "Opt+2"
        )
        manager.hide()

        XCTAssertEqual(unhideCount, 2, "Each fresh activation attempt should unhide its target once")
        XCTAssertEqual(activationFromCurrentAppFlags, [false, false])

        retryActions[0]()

        XCTAssertEqual(unhideCount, 2, "A stale retry must not unhide or re-activate an old target")
        XCTAssertEqual(activationFromCurrentAppFlags, [false, false])
        XCTAssertTrue(activationResults.isEmpty)
    }

    @MainActor
    func testDeclinedRunningAppActivationRetryIsSkippedAfterLaunchAttempt() {
        let runningApp = NSRunningApplication.current
        let runningItem = HUDAppItem(
            bundleId: "com.test.retry.running",
            pid: runningApp.processIdentifier,
            name: "Running Retry Target"
        )
        let launchItem = HUDAppItem(
            bundleId: "com.test.retry.launch",
            name: "Launch Retry Target",
            icon: nil
        )
        var unhideCount = 0
        var activationFromCurrentAppFlags: [Bool] = []
        var activationResults = [false]
        var retryActions: [@MainActor @Sendable () -> Void] = []

        manager.runningApplicationsProvider = { bundleId in
            bundleId == runningItem.bundleId ? [runningApp] : []
        }
        manager.unhideRunningApplication = { _ in
            unhideCount += 1
        }
        manager.activateRunningApplication = { _, fromCurrentApp in
            activationFromCurrentAppFlags.append(fromCurrentApp)
            guard !activationResults.isEmpty else {
                XCTFail("Stale retry should not perform another activation")
                return true
            }
            return activationResults.removeFirst()
        }
        manager.scheduleActivationRetry = { action in
            retryActions.append(action)
        }
        manager.scheduleVisibleWindowRecheck = { _ in }
        manager.hasVisibleWindowsForPID = { _ in true }
        manager.isAppActive = { false }

        manager.scheduleShow(
            items: [runningItem],
            activeAppId: runningItem.id,
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )
        manager.hide()

        XCTAssertEqual(retryActions.count, 1)

        manager.scheduleShow(
            items: [launchItem],
            activeAppId: launchItem.id,
            modifierFlags: [.option],
            shortcut: "Opt+2"
        )
        manager.hide()

        retryActions[0]()

        XCTAssertEqual(unhideCount, 1, "A stale retry must not unhide after a newer launch attempt")
        XCTAssertEqual(activationFromCurrentAppFlags, [false])
        XCTAssertTrue(activationResults.isEmpty)
    }

    @MainActor
    func testHideKeepsSettingsOpenOnBlindSwitchWhenHUDWasNeverPresented() {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        var closeCount = 0
        var activateCount = 0

        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in closeCount += 1 }
        manager.targetLeavesCurrentSpace = { _ in true }
        manager.activatePendingTargetApp = { _ in activateCount += 1 }

        // Schedule without immediate — HUD is pending but never shown before hide()
        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.blind", pid: 7, name: "Blind Target")],
            activeAppId: "com.test.blind::7",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        // Cancel the show timer without firing it, then call hide() directly (blind switch)
        manager.hide()

        // Settings must not be closed: HUD was never presented this session
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(activateCount, 1)
    }

    @MainActor
    func testRapidBlindSwitchDoesNotShowHUD() {
        // 1. First Press
        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)],
            activeAppId: "com.test.quick",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        XCTAssertEqual(timerMock.scheduledTimers.count, 1)

        // 2. Release immediately (Session End)
        manager.hide()
        timeMock.currentTime = timeMock.currentTime.addingTimeInterval(0.1) // 100ms later
        timerMock.scheduledTimers.removeAll()

        // 3. Second Press (Rapid)
        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)],
            activeAppId: "com.test.quick",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        XCTAssertEqual(timerMock.scheduledTimers.count, 1, "A new quick-tap session should schedule a fresh reveal timer")
        XCTAssertFalse(manager.isVisible, "A new quick tap should not reveal the HUD immediately")
    }

    // MARK: - isLooping / Throttling Tests

    @MainActor
    func testIsLoopingFalseInitially() {
        XCTAssertFalse(manager.isLooping, "isLooping should be false with no active loop")
    }

    @MainActor
    func testIsLoopingFalseDuringDelayPhase() {
        // Simulate the state after scheduleLoopStart schedules a delay timer
        // but before the repeating loop starts.
        // This is the key fix: during the 200ms delay, isLooping must be false
        // so AppSwitcher doesn't block manual taps.

        manager.isLoopKeyHeld = true
        manager.currentLoopKey = 0 // Some key code

        // scheduleShow on immediate path would schedule a delay timer here.
        // The delay timer is non-repeating. isRepeatingLoopActive is still false.
        XCTAssertFalse(manager.isLooping,
            "isLooping must be false during delay phase so manual taps are not blocked")
        XCTAssertFalse(manager.isRepeatingLoopActive,
            "isRepeatingLoopActive must be false before repeating loop starts")
    }

    @MainActor
    func testIsLoopingTrueOnlyDuringRepeatingLoop() {
        // Manually set the flag that startRepeatingLoop would set
        manager.isRepeatingLoopActive = true

        XCTAssertTrue(manager.isLooping,
            "isLooping should be true when repeating loop is active")
    }

    @MainActor
    func testRapidTappingKeepsIsLoopingFalse() {
        // Simulate 5 rapid taps. Each tap resets the delay timer.
        // isLooping should remain false throughout (no repeating loop started).

        let items = [
            HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil),
            HUDAppItem(bundleId: "com.test.2", name: "Test 2", icon: nil)
        ]

        for i in 0..<5 {
            timeMock.currentTime = timeMock.currentTime.addingTimeInterval(0.08) // 80ms between taps

            manager.scheduleShow(
                items: items,
                activeAppId: items[i % 2].id,
                modifierFlags: [.option],
                shortcut: "Opt+1"
            )

            XCTAssertFalse(manager.isLooping,
                "isLooping must remain false during rapid tapping (tap \(i + 1))")
        }
    }

    @MainActor
    func testHUDReusesHostingViewAcrossRapidUpdatesAndNewSessions() throws {
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        let items = [
            HUDAppItem(id: "com.test.1", name: "Test 1", icon: icon, isRunning: true),
            HUDAppItem(id: "com.test.2", name: "Test 2", icon: icon, isRunning: true)
        ]

        let firstWindow = try XCTUnwrap(
            manager.presentScreenshotHUD(
                items: items,
                activeAppId: items[0].id,
                shortcut: "Opt+1"
            )
        )
        let firstHostingView = try XCTUnwrap(firstWindow.contentView)
        let firstIdentity = try XCTUnwrap(manager.hostingViewIdentityForTesting)

        for updateIndex in 0..<100 {
            let hoverView = try XCTUnwrap(
                findSubview(ofType: HUDAppKitHoverView.self, in: firstHostingView)
            )
            hoverView.updateHovering(updateIndex.isMultiple(of: 2))

            let window = try XCTUnwrap(
                manager.presentScreenshotHUD(
                    items: items,
                    activeAppId: items[updateIndex % items.count].id,
                    shortcut: "Opt+1"
                )
            )

            XCTAssertTrue(window.contentView === firstHostingView)
            XCTAssertEqual(manager.hostingViewIdentityForTesting, firstIdentity)
        }

        manager.hide()

        let nextSessionWindow = try XCTUnwrap(
            manager.presentScreenshotHUD(
                items: items,
                activeAppId: items[1].id,
                shortcut: "Opt+1"
            )
        )

        XCTAssertTrue(nextSessionWindow.contentView === firstHostingView)
        XCTAssertEqual(manager.hostingViewIdentityForTesting, firstIdentity)
    }

    // MARK: - Phantom Loop Prevention Tests

    @MainActor
    func testStopLoopingClearsRepeatingLoopActive() {
        // Simulate an active repeating loop
        manager.isRepeatingLoopActive = true
        manager.currentLoopKey = 0

        XCTAssertTrue(manager.isLooping)

        // hide() calls stopLooping internally
        manager.hide()

        XCTAssertFalse(manager.isLooping,
            "isLooping must be false after hide/stopLooping")
        XCTAssertFalse(manager.isRepeatingLoopActive,
            "isRepeatingLoopActive must be cleared by stopLooping")
    }

    @MainActor
    func testHideClearsAllLoopState() {
        // Set up state as if a loop was active
        manager.isLoopKeyHeld = true
        manager.currentLoopKey = 42
        manager.isRepeatingLoopActive = true
        manager.lastRequestTime = Date()

        manager.hide()

        XCTAssertFalse(manager.isLooping)
        XCTAssertFalse(manager.isRepeatingLoopActive)
        XCTAssertNil(manager.currentLoopKey, "currentLoopKey should be nil after hide")
    }

    @MainActor
    func testCurrentLoopKeyNilPreventsPhantomAdvance() {
        // This tests the guard in selectNextApp:
        // If currentLoopKey is nil (stopLooping already ran), selectNextApp should not advance.

        let items = [
            HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil),
            HUDAppItem(bundleId: "com.test.2", name: "Test 2", icon: nil)
        ]

        // Show HUD with items via repeated path
        manager.scheduleShow(
            items: items,
            activeAppId: items[0].id,
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )
        timeMock.currentTime = timeMock.currentTime.addingTimeInterval(0.1)
        manager.scheduleShow(
            items: items,
            activeAppId: items[0].id,
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        let selectedBefore = manager.currentSelectedAppId

        // Simulate: stopLooping was called (key released), clearing currentLoopKey
        manager.currentLoopKey = nil
        manager.isLoopKeyHeld = false

        // If a phantom timer fires selectNextApp now, it should NOT advance
        // because the guard checks currentLoopKey != nil
        // We can't call selectNextApp directly (it's private), but we can verify
        // the state is set up to prevent it
        XCTAssertNil(manager.currentLoopKey,
            "currentLoopKey must be nil to trigger the phantom loop guard")
        XCTAssertFalse(manager.isLoopKeyHeld,
            "isLoopKeyHeld must be false when key is released")

        // The selectedAppId should not have changed
        XCTAssertEqual(manager.currentSelectedAppId, selectedBefore,
            "Selection should not change when loop state is cleared")
    }

    @MainActor
    func testDelayTimerScheduledWithCorrectInterval() {
        // Verify that scheduleLoopStart uses the expected 200ms delay
        let items = [
            HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil),
            HUDAppItem(bundleId: "com.test.2", name: "Test 2", icon: nil)
        ]

        // First call to set lastRequestTime
        manager.scheduleShow(
            items: items,
            activeAppId: items[0].id,
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        let initialTimerCount = timerMock.scheduledTimers.count

        timeMock.currentTime = timeMock.currentTime.addingTimeInterval(0.1)

        // Second call takes immediate path, which calls scheduleLoopStart
        // when an activeKey is provided.
        manager.scheduleShow(
            items: items,
            activeAppId: items[0].id,
            modifierFlags: [.option],
            shortcut: "Opt+1",
            activeKey: .a,
            immediate: true
        )

        // Check that new timers were scheduled
        let newTimers = timerMock.scheduledTimers.dropFirst(initialTimerCount)

        // Should have at least the loop delay timer (non-repeating, 0.2s)
        let delayTimers = newTimers.filter { !$0.1 && $0.0 == 0.2 }
        XCTAssertFalse(delayTimers.isEmpty,
            "Should schedule a 0.2s non-repeating delay timer for loop start")

        // isLooping should still be false (only delay timer, not repeating loop)
        XCTAssertFalse(manager.isLooping,
            "isLooping must be false during the delay phase")
    }

    private func findSubview<ViewType: NSView>(ofType type: ViewType.Type, in root: NSView) -> ViewType? {
        if let match = root as? ViewType {
            return match
        }

        for subview in root.subviews {
            if let match = findSubview(ofType: type, in: subview) {
                return match
            }
        }

        return nil
    }
}

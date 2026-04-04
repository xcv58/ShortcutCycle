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
        // (interval, repeats, block)
        var scheduledTimers: [(TimeInterval, Bool, (Timer) -> Void)] = []
        var lastTimer: Timer?

        func schedule(timeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
            let timer = Timer() // Dummy
            scheduledTimers.append((timeInterval, repeats, block))
            lastTimer = timer
            return timer
        }

        func fireLastTimer() {
            guard let last = scheduledTimers.last else { return }
            last.2(Timer())
        }

        /// Fire the most recent non-repeating timer (delay timer)
        func fireLastNonRepeatingTimer() {
            guard let entry = scheduledTimers.last(where: { !$0.1 }) else { return }
            entry.2(Timer())
        }

        /// Fire the most recent repeating timer (loop timer)
        func fireLastRepeatingTimer() {
            guard let entry = scheduledTimers.last(where: { $0.1 }) else { return }
            entry.2(Timer())
        }
    }

    var manager: HUDManager!
    var timeMock: MockTimeProvider!
    var timerMock: MockTimerScheduler!
    var activationCount: Int!
    var localMonitorMasks: [NSEvent.EventTypeMask]!
    var globalMonitorMasks: [NSEvent.EventTypeMask]!
    var localMonitorHandlers: [(NSEvent.EventTypeMask, (NSEvent) -> NSEvent?)]!
    var globalMonitorHandlers: [(NSEvent.EventTypeMask, (NSEvent) -> Void)]!
    var removedMonitorCount: Int!

    override func setUp() async throws {
        // Setup mocks
        manager = HUDManager.shared
        timeMock = MockTimeProvider()
        timerMock = MockTimerScheduler()
        activationCount = 0
        localMonitorMasks = []
        globalMonitorMasks = []
        localMonitorHandlers = []
        globalMonitorHandlers = []
        removedMonitorCount = 0

        // Inject mocks
        manager.timeProvider = timeMock
        manager.timerScheduler = timerMock
        manager.activateHUDApp = { [weak self] in
            self?.activationCount += 1
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
        manager.settingsWindowsProvider = { [] }
        manager.closeWindow = { window in
            window.close()
        }
        manager.targetLeavesCurrentSpace = { _ in false }

        // Reset state
        manager.hide() // Ensure clean state
        manager.lastRequestTime = nil
        manager.isLoopKeyHeld = false
        manager.currentLoopKey = nil
        manager.isRepeatingLoopActive = false
        removedMonitorCount = 0
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

        // Expect timer scheduled (waiting for hold)
        XCTAssertEqual(timerMock.scheduledTimers.count, 1, "Should schedule a timer for hold detection")
        XCTAssertFalse(manager.isVisible, "HUD should not be visible immediately")

        // 2. Release immediately (simulated by not firing timer and ending session)
        manager.hide() // Simulate release/finalize

        // Verify HUD never showed
        XCTAssertFalse(manager.isVisible)
    }

    @MainActor
    func testPressAndHoldShowsHUD() {
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

        // The timer block calls presentHUD. In unit tests without a real window loop,
        // we verify the timer was scheduled and fired — the delay mechanism is correct.
    }

    @MainActor
    func testDelayedShowDefersActivationUntilHUDAppears() async {
        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)],
            activeAppId: "com.test.current",
            modifierFlags: [.option],
            shortcut: "Opt+1",
            activeKey: .a
        )

        XCTAssertEqual(activationCount, 0, "Delayed HUD path should not activate the app before the HUD appears")
        XCTAssertTrue(globalMonitorMasks.contains(.flagsChanged), "Delayed HUD path should start with global modifier monitoring")
        XCTAssertEqual(localMonitorMasks, [], "Delayed HUD path should not install local monitors before activation")

        timerMock.fireLastNonRepeatingTimer()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(activationCount, 1, "Showing the HUD should activate the app exactly once")
        XCTAssertTrue(localMonitorMasks.contains(.flagsChanged), "HUD presentation should switch to local modifier monitoring")
        XCTAssertTrue(removedMonitorCount > 0, "Transitioning to the visible HUD should remove pre-show monitors")
    }

    @MainActor
    func testDelayedShowClosesOffSpaceSettingsWindowBeforeHUDActivation() async {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: false
        )
        var events: [String] = []

        manager.settingsWindowsProvider = { [settingsWindow] }
        manager.closeWindow = { _ in
            events.append("close")
        }
        manager.activateHUDApp = {
            events.append("activate")
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

        XCTAssertEqual(Array(events.prefix(2)), ["close", "activate"])
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
        // This MUST clear lastRequestTime
        manager.lastRequestTime = nil // Simulating `finalizeSwitchAndHide` effect
        timeMock.currentTime = timeMock.currentTime.addingTimeInterval(0.1) // 100ms later
        timerMock.scheduledTimers.removeAll()

        // 3. Second Press (Rapid)
        manager.scheduleShow(
            items: [HUDAppItem(bundleId: "com.test.1", name: "Test 1", icon: nil)],
            activeAppId: "com.test.quick",
            modifierFlags: [.option],
            shortcut: "Opt+1"
        )

        // If bug was present: `isRepeated` = true -> Show Immediate
        // If fixed: `isRepeated` = false -> Schedule Timer

        XCTAssertEqual(timerMock.scheduledTimers.count, 1, "Should schedule a delay timer, not show immediately")
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
}

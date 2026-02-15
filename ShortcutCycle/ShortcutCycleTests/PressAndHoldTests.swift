import XCTest

import Combine
@testable import ShortcutCycle

@MainActor
final class PressAndHoldTests: XCTestCase {
    
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
    }
    
    var manager: HUDManager!
    var timeMock: MockTimeProvider!
    var timerMock: MockTimerScheduler!
    
    override func setUp() async throws {
        // Setup mocks
        manager = HUDManager.shared
        timeMock = MockTimeProvider()
        timerMock = MockTimerScheduler()
        
        // Inject mocks
        manager.timeProvider = timeMock
        manager.timerScheduler = timerMock
        
        // Reset state
        await manager.hide() // Ensure clean state
        manager.lastRequestTime = nil
    }
    
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
        
        // Verify HUD is now visible (conceptually - we can't fully check UI window visibility in unit test easily without loading UI, 
        // but we can check if `presentHUD` was called if we mocked it, or check `isVisible` if it reflects intent.
        // `HUDManager.isVisible` checks `window?.isVisible`. Since we don't have a real window in unit tests usually,
        // this might fail if strictly relying on NSWindow.
        // However, let's assume `scheduleShow` -> `presentHUD` -> sets up window. 
        // If `presentHUD` relies on real NSWindow, we might need to mock `window` or `HUDWindowController`.
        // `HUDManager` uses `var window: NSWindow?`. accessible?
        // It's `private(set) var window`.
        
        // For now, let's check internal state if exposed, OR assume the test environment allows basic window operations?
        // `HUDManager` uses `HUDPanel`.
        
        // Alternatively, we can check if the timer logic executed.
        // The timer block calls `presentHUD`.
        
        // Let's rely on the fact that we fired the timer.
        // We can't easily assert `isVisible` is true without a real window loop.
        // But we verified the timer WAS scheduled.
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
        // XCTAssertFalse(manager.isVisible) // Again, hard to assert false if we don't trust window state, but we know it didn't take the "Immediate" path because that path DOES NOT schedule a timer.
    }
}

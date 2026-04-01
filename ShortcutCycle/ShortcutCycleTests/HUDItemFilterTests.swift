import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

final class HUDItemFilterTests: XCTestCase {

    // MARK: - Helpers

    private func item(bundleId: String, pid: pid_t) -> HUDAppItem {
        HUDAppItem(bundleId: bundleId, pid: pid)
    }

    private func nonRunning(bundleId: String) -> HUDAppItem {
        HUDAppItem(bundleId: bundleId, name: "App", icon: nil)
    }

    // MARK: - Single-instance cases

    func testSingleInstanceVisible() {
        let a = item(bundleId: "com.test.app", pid: 100)
        let result = HUDItemFilter.filter([a],
            isHidden: { _ in false },
            hasVisibleWindows: { _ in true }
        )
        XCTAssertEqual(result, [a])
    }

    func testSingleInstanceHiddenCmdH() {
        let a = item(bundleId: "com.test.app", pid: 100)
        let result = HUDItemFilter.filter([a],
            isHidden: { _ in true },
            hasVisibleWindows: { _ in false }
        )
        // Single-instance: always kept regardless of window state
        XCTAssertEqual(result, [a])
    }

    func testSingleInstanceMinimized() {
        let a = item(bundleId: "com.test.app", pid: 100)
        let result = HUDItemFilter.filter([a],
            isHidden: { _ in false },
            hasVisibleWindows: { _ in false }
        )
        // Single-instance: always kept regardless of window state
        XCTAssertEqual(result, [a])
    }

    func testNonRunningItemAlwaysKept() {
        let a = nonRunning(bundleId: "com.test.app")
        let result = HUDItemFilter.filter([a],
            isHidden: { _ in false },
            hasVisibleWindows: { _ in false }
        )
        XCTAssertEqual(result, [a])
    }

    // MARK: - Multi-profile cases

    func testMultiProfileAllVisible() {
        let a = item(bundleId: "com.test.browser", pid: 100)
        let b = item(bundleId: "com.test.browser", pid: 200)
        let result = HUDItemFilter.filter([a, b],
            isHidden: { _ in false },
            hasVisibleWindows: { _ in true }
        )
        XCTAssertEqual(Set(result.map(\.id)), Set([a.id, b.id]))
    }

    func testMultiProfileOneVisibleOneMinimized() {
        let visible = item(bundleId: "com.test.browser", pid: 100)
        let minimized = item(bundleId: "com.test.browser", pid: 200)
        let result = HUDItemFilter.filter([visible, minimized],
            isHidden: { _ in false },
            hasVisibleWindows: { pid in pid == 100 }
        )
        XCTAssertEqual(result, [visible])
    }

    func testMultiProfileOneVisibleOneHiddenCmdH() {
        let visible = item(bundleId: "com.test.browser", pid: 100)
        let hidden = item(bundleId: "com.test.browser", pid: 200)
        let result = HUDItemFilter.filter([visible, hidden],
            isHidden: { pid in pid == 200 },
            hasVisibleWindows: { pid in pid == 100 }
        )
        // Both kept: visible has windows, hidden (Cmd+H) is kept for reliable restore
        XCTAssertEqual(Set(result.map(\.id)), Set([visible.id, hidden.id]))
    }

    func testMultiProfileOneHiddenOneMinimized() {
        let hidden = item(bundleId: "com.test.browser", pid: 100)
        let minimized = item(bundleId: "com.test.browser", pid: 200)
        let result = HUDItemFilter.filter([hidden, minimized],
            isHidden: { pid in pid == 100 },
            hasVisibleWindows: { _ in false }
        )
        // Hidden (Cmd+H) kept, minimized filtered
        XCTAssertEqual(result, [hidden])
    }

    func testMultiProfileAllMinimizedKeepsOne() {
        let a = item(bundleId: "com.test.browser", pid: 100)
        let b = item(bundleId: "com.test.browser", pid: 200)
        let result = HUDItemFilter.filter([a, b],
            isHidden: { _ in false },
            hasVisibleWindows: { _ in false }
        )
        // All minimized → fallback keeps the first original so the app stays in the HUD
        XCTAssertEqual(result, [a])
    }

    func testMultiProfileAllHiddenCmdHKeepsAll() {
        let a = item(bundleId: "com.test.browser", pid: 100)
        let b = item(bundleId: "com.test.browser", pid: 200)
        let result = HUDItemFilter.filter([a, b],
            isHidden: { _ in true },
            hasVisibleWindows: { _ in false }
        )
        XCTAssertEqual(Set(result.map(\.id)), Set([a.id, b.id]))
    }

    // MARK: - Mixed bundle IDs

    func testMixedBundleIds() {
        let single = item(bundleId: "com.test.single", pid: 100)
        let profile1 = item(bundleId: "com.test.browser", pid: 200)
        let profile2 = item(bundleId: "com.test.browser", pid: 300)
        let result = HUDItemFilter.filter([single, profile1, profile2],
            isHidden: { _ in false },
            hasVisibleWindows: { pid in pid == 100 || pid == 200 }
        )
        // single kept (single-instance always kept)
        // profile1 kept (visible)
        // profile2 filtered (minimized multi-profile)
        XCTAssertTrue(result.contains(single))
        XCTAssertTrue(result.contains(profile1))
        XCTAssertFalse(result.contains(profile2))
    }

    func testRelativeOrderPreserved() {
        let a = item(bundleId: "com.test.browser", pid: 100)
        let b = item(bundleId: "com.test.browser", pid: 200)
        let c = item(bundleId: "com.test.browser", pid: 300)
        let result = HUDItemFilter.filter([a, b, c],
            isHidden: { _ in false },
            hasVisibleWindows: { pid in pid == 100 || pid == 300 }
        )
        // b is minimized and filtered; a and c retained in order
        XCTAssertEqual(result, [a, c])
    }

    func testNonRunningMixedWithMultiProfile() {
        let nonRun = nonRunning(bundleId: "com.test.browser")
        let running = item(bundleId: "com.test.browser", pid: 100)
        // Even though same bundle ID appears twice, the non-running item has no PID
        // and is treated as always-kept by the single-instance guard
        let result = HUDItemFilter.filter([nonRun, running],
            isHidden: { _ in false },
            hasVisibleWindows: { _ in false }
        )
        // nonRun has no pid → always kept; running has pid but only 1 item in group with pid?
        // Actually: both share bundleId "com.test.browser", count > 1.
        // nonRun.pid == nil → guard fails → kept.
        // running.pid == 100 → group count is 2 → isHidden false, no visible windows → filtered.
        // Fallback: no result for that bundleId, so appends first original (nonRun).
        // So result should contain nonRun exactly once.
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, nonRun.id)
    }
}

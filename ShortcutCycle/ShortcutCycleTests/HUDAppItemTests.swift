import XCTest
import AppKit
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

final class HUDAppItemTests: XCTestCase {

    // MARK: - Non-running app init

    func testInitWithBundleId() {
        let item = HUDAppItem(bundleId: "com.test.app", name: "Test App", icon: nil)

        XCTAssertEqual(item.id, "com.test.app")
        XCTAssertEqual(item.bundleId, "com.test.app")
        XCTAssertEqual(item.name, "Test App")
        XCTAssertNil(item.pid)
        XCTAssertNil(item.icon)
        XCTAssertFalse(item.isRunning)
    }

    func testInitWithBundleIdAndIcon() {
        let icon = NSImage()
        let item = HUDAppItem(bundleId: "com.test.app", name: "Test", icon: icon)

        XCTAssertNotNil(item.icon)
        XCTAssertEqual(item.icon, icon)
    }

    // MARK: - Legacy init

    func testLegacyInit() {
        let item = HUDAppItem(id: "com.legacy.app", name: "Legacy", icon: nil, isRunning: true)

        XCTAssertEqual(item.id, "com.legacy.app")
        XCTAssertEqual(item.bundleId, "com.legacy.app")
        XCTAssertNil(item.pid)
        XCTAssertEqual(item.name, "Legacy")
        XCTAssertNil(item.icon)
        XCTAssertTrue(item.isRunning)
    }

    func testLegacyInitNotRunning() {
        let item = HUDAppItem(id: "com.test", name: "Test", icon: nil, isRunning: false)

        XCTAssertFalse(item.isRunning)
    }

    // MARK: - Running app init

    func testInitWithRunningApp() {
        // Use the current process as a running app (always available in tests)
        let runningApp = NSRunningApplication.current

        let item = HUDAppItem(runningApp: runningApp)

        let expectedBundleId = runningApp.bundleIdentifier ?? ""
        XCTAssertEqual(item.bundleId, expectedBundleId)
        XCTAssertEqual(item.pid, runningApp.processIdentifier)
        XCTAssertEqual(item.id, "\(expectedBundleId)::\(runningApp.processIdentifier)")
        XCTAssertTrue(item.isRunning)
        // Name should fall back to localizedName or "App"
        XCTAssertFalse(item.name.isEmpty)
    }

    func testInitWithRunningAppCustomNameAndIcon() {
        let runningApp = NSRunningApplication.current
        let customIcon = NSImage()

        let item = HUDAppItem(runningApp: runningApp, name: "Custom Name", icon: customIcon)

        XCTAssertEqual(item.name, "Custom Name")
        XCTAssertEqual(item.icon, customIcon)
        XCTAssertTrue(item.isRunning)
    }

    // MARK: - Equatable

    func testEqualWhenSameId() {
        let item1 = HUDAppItem(bundleId: "com.test", name: "Name 1", icon: nil)
        let item2 = HUDAppItem(bundleId: "com.test", name: "Name 2", icon: nil)

        // Equatable is based on id only
        XCTAssertEqual(item1, item2)
    }

    func testNotEqualWhenDifferentId() {
        let item1 = HUDAppItem(bundleId: "com.test.a", name: "Same", icon: nil)
        let item2 = HUDAppItem(bundleId: "com.test.b", name: "Same", icon: nil)

        XCTAssertNotEqual(item1, item2)
    }

    func testEqualityAcrossInitializers() {
        let item1 = HUDAppItem(bundleId: "com.test", name: "A", icon: nil)
        let item2 = HUDAppItem(id: "com.test", name: "B", icon: nil, isRunning: true)

        // Same id, different init → should be equal
        XCTAssertEqual(item1, item2)
    }

    // MARK: - Per-window properties on existing initializers

    func testNonRunningInitHasNilWindowProperties() {
        let item = HUDAppItem(bundleId: "com.test", name: "Test", icon: nil)

        XCTAssertNil(item.windowTitle)
        XCTAssertNil(item.windowIndex)
        XCTAssertNil(item.appName)
    }

    func testLegacyInitHasNilWindowProperties() {
        let item = HUDAppItem(id: "com.test", name: "Test", icon: nil, isRunning: true)

        XCTAssertNil(item.windowTitle)
        XCTAssertNil(item.windowIndex)
        XCTAssertNil(item.appName)
    }

    func testRunningAppInitHasNilWindowProperties() {
        let item = HUDAppItem(runningApp: NSRunningApplication.current)

        XCTAssertNil(item.windowTitle)
        XCTAssertNil(item.windowIndex)
        XCTAssertNil(item.appName)
    }

    // MARK: - Per-window init (testable)

    func testPerWindowInitWithTitle() {
        let item = HUDAppItem(
            bundleId: "com.chrome",
            pid: 1234,
            windowTitle: "GitHub - Google Chrome",
            windowIndex: 0,
            name: "Google Chrome"
        )

        XCTAssertEqual(item.id, "com.chrome::1234::w0")
        XCTAssertEqual(item.bundleId, "com.chrome")
        XCTAssertEqual(item.pid, 1234)
        XCTAssertEqual(item.name, "GitHub - Google Chrome")
        XCTAssertEqual(item.windowTitle, "GitHub - Google Chrome")
        XCTAssertEqual(item.windowIndex, 0)
        XCTAssertEqual(item.appName, "Google Chrome")
        XCTAssertTrue(item.isRunning)
        XCTAssertNil(item.icon)
    }

    func testPerWindowInitWithNilTitle() {
        let item = HUDAppItem(
            bundleId: "com.app",
            pid: 500,
            windowTitle: nil,
            windowIndex: 2,
            name: "MyApp"
        )

        // Nil title falls back to "AppName - Window N+1"
        XCTAssertEqual(item.name, "MyApp - Window 3")
        XCTAssertNil(item.windowTitle)
        XCTAssertEqual(item.windowIndex, 2)
        XCTAssertEqual(item.appName, "MyApp")
        XCTAssertEqual(item.id, "com.app::500::w2")
    }

    func testPerWindowInitWithIcon() {
        let icon = NSImage()
        let item = HUDAppItem(
            bundleId: "com.app",
            pid: 100,
            windowTitle: "Window",
            windowIndex: 0,
            name: "App",
            icon: icon
        )

        XCTAssertEqual(item.icon, icon)
    }

    func testPerWindowInitViaRunningApp() {
        let runningApp = NSRunningApplication.current
        let item = HUDAppItem(
            runningApp: runningApp,
            windowTitle: "Test Window",
            windowIndex: 0,
            name: "Test"
        )

        let expectedBundleId = runningApp.bundleIdentifier ?? ""
        XCTAssertEqual(item.bundleId, expectedBundleId)
        XCTAssertEqual(item.pid, runningApp.processIdentifier)
        XCTAssertEqual(item.id, "\(expectedBundleId)::\(runningApp.processIdentifier)::w0")
        XCTAssertEqual(item.windowTitle, "Test Window")
        XCTAssertEqual(item.windowIndex, 0)
        XCTAssertEqual(item.appName, "Test")
        XCTAssertTrue(item.isRunning)
    }

    func testPerWindowInitViaRunningAppDefaultName() {
        let runningApp = NSRunningApplication.current
        // Pass nil for name and icon to exercise the fallback paths
        let item = HUDAppItem(
            runningApp: runningApp,
            windowTitle: "Window",
            windowIndex: 1
        )

        let expectedBundleId = runningApp.bundleIdentifier ?? ""
        XCTAssertEqual(item.id, "\(expectedBundleId)::\(runningApp.processIdentifier)::w1")
        // appName should fall back to localizedName or "App"
        XCTAssertNotNil(item.appName)
        XCTAssertFalse(item.appName!.isEmpty)
        XCTAssertEqual(item.windowTitle, "Window")
        XCTAssertTrue(item.isRunning)
    }

    func testPerWindowEqualityById() {
        let item1 = HUDAppItem(bundleId: "com.app", pid: 100, windowTitle: "A", windowIndex: 0, name: "App")
        let item2 = HUDAppItem(bundleId: "com.app", pid: 100, windowTitle: "B", windowIndex: 0, name: "App")

        // Same id (same bundleId::pid::w0) → equal
        XCTAssertEqual(item1, item2)
    }

    func testPerWindowDifferentIndexNotEqual() {
        let item1 = HUDAppItem(bundleId: "com.app", pid: 100, windowTitle: "A", windowIndex: 0, name: "App")
        let item2 = HUDAppItem(bundleId: "com.app", pid: 100, windowTitle: "A", windowIndex: 1, name: "App")

        // Different window index → different id → not equal
        XCTAssertNotEqual(item1, item2)
    }
}

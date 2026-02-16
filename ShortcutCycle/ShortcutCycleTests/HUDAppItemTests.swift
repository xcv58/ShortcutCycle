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
}

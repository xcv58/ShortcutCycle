import AppKit
import XCTest
@testable import ShortcutCycle

@MainActor
final class SettingsWindowLifecycleCoordinatorTests: XCTestCase {
    func testVisibleOffSpaceSettingsWindowReturnsMatchingWindow() {
        let window = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: false
        )

        XCTAssertTrue(
            SettingsWindowLifecycleCoordinator.visibleOffSpaceSettingsWindow(in: [window]) === window
        )
    }

    func testVisibleOffSpaceSettingsWindowIgnoresCurrentSpaceHiddenAndNonSettingsWindows() {
        XCTAssertNil(
            SettingsWindowLifecycleCoordinator.visibleOffSpaceSettingsWindow(
                in: [
                    MockWindow(
                        identifier: NSUserInterfaceItemIdentifier("settings"),
                        isVisible: true,
                        isOnActiveSpace: true
                    ),
                    MockWindow(
                        identifier: NSUserInterfaceItemIdentifier("settings"),
                        isVisible: false,
                        isOnActiveSpace: false
                    ),
                    MockWindow(
                        identifier: NSUserInterfaceItemIdentifier("other"),
                        isVisible: true,
                        isOnActiveSpace: false
                    )
                ]
            )
        )
    }

    func testVisibleSettingsWindowReturnsCurrentSpaceSettingsWindow() {
        let window = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )

        XCTAssertTrue(
            SettingsWindowLifecycleCoordinator.visibleSettingsWindow(in: [window]) === window
        )
    }

    func testVisibleSettingsWindowIgnoresHiddenAndNonSettingsWindows() {
        XCTAssertNil(
            SettingsWindowLifecycleCoordinator.visibleSettingsWindow(
                in: [
                    MockWindow(
                        identifier: NSUserInterfaceItemIdentifier("settings"),
                        isVisible: false,
                        isOnActiveSpace: true
                    ),
                    MockWindow(
                        identifier: NSUserInterfaceItemIdentifier("other"),
                        isVisible: true,
                        isOnActiveSpace: true
                    )
                ]
            )
        )
    }

    func testAppPolicyDockReopenDependsOnlyOnVisibleWindows() {
        XCTAssertTrue(
            SettingsWindowAppPolicy.shouldHandleDockReopen(
                hasVisibleWindows: false
            )
        )

        XCTAssertFalse(
            SettingsWindowAppPolicy.shouldHandleDockReopen(
                hasVisibleWindows: true
            )
        )
    }

    func testCoordinatorIdentifiesSettingsWindowByIdentifier() {
        let settingsWindow = NSWindow()
        settingsWindow.identifier = NSUserInterfaceItemIdentifier("settings")
        let otherWindow = NSWindow()
        otherWindow.identifier = NSUserInterfaceItemIdentifier("other")

        XCTAssertTrue(SettingsWindowLifecycleCoordinator.isSettingsWindow(settingsWindow))
        XCTAssertFalse(SettingsWindowLifecycleCoordinator.isSettingsWindow(otherWindow))
    }

    func testCoordinatorDockReopenWrapperDependsOnlyOnVisibleWindows() {
        XCTAssertTrue(
            SettingsWindowLifecycleCoordinator.shouldHandleDockReopen(
                hasVisibleWindows: false
            )
        )

        XCTAssertFalse(
            SettingsWindowLifecycleCoordinator.shouldHandleDockReopen(
                hasVisibleWindows: true
            )
        )
    }
}

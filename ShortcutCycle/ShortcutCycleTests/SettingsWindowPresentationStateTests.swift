import AppKit
import XCTest
@testable import ShortcutCycle

@MainActor
final class SettingsWindowPresentationStateTests: XCTestCase {
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

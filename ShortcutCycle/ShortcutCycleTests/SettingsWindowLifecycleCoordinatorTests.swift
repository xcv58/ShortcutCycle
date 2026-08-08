import AppKit
import KeyboardShortcuts
import XCTest
@testable import ShortcutCycle

@MainActor
final class SettingsWindowLifecycleCoordinatorTests: XCTestCase {
    func testAnyVisibleSettingsWindowReturnsWindowOnAnySpace() {
        let window = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )

        XCTAssertTrue(
            SettingsWindowLifecycleCoordinator.anyVisibleSettingsWindow(in: [window]) === window
        )
    }

    func testAnyVisibleSettingsWindowIgnoresHiddenAndNonSettingsWindows() {
        XCTAssertNil(
            SettingsWindowLifecycleCoordinator.anyVisibleSettingsWindow(
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

    func testCoordinatorIdentifiesSettingsWindowByIdentifier() {
        let settingsWindow = NSWindow()
        settingsWindow.identifier = NSUserInterfaceItemIdentifier("settings")
        let otherWindow = NSWindow()
        otherWindow.identifier = NSUserInterfaceItemIdentifier("other")

        XCTAssertTrue(SettingsWindowLifecycleCoordinator.isSettingsWindow(settingsWindow))
        XCTAssertFalse(SettingsWindowLifecycleCoordinator.isSettingsWindow(otherWindow))
    }

    func testToggleActionOpensWhenSettingsWindowIsMissingOrHidden() {
        let hiddenWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: false,
            isOnActiveSpace: true,
            isKeyWindow: true
        )
        let nonSettingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("other"),
            isVisible: true,
            isOnActiveSpace: true,
            isKeyWindow: true
        )

        XCTAssertEqual(SettingsWindowLifecycleCoordinator.toggleAction(for: nil), .open)
        XCTAssertEqual(SettingsWindowLifecycleCoordinator.toggleAction(for: hiddenWindow), .open)
        XCTAssertEqual(SettingsWindowLifecycleCoordinator.toggleAction(for: nonSettingsWindow), .open)
    }

    func testToggleActionFocusesVisibleBackgroundSettingsWindow() {
        let window = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )

        XCTAssertEqual(SettingsWindowLifecycleCoordinator.toggleAction(for: window), .focus)
    }

    func testToggleActionDismissesVisibleKeySettingsWindow() {
        let window = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true,
            isKeyWindow: true
        )

        XCTAssertEqual(SettingsWindowLifecycleCoordinator.toggleAction(for: window), .dismiss)
    }

    func testToggleActionFocusesSettingsWindowWhenVisibleSheetIsAttached() {
        let sheet = MockWindow(
            identifier: nil,
            isVisible: true,
            isOnActiveSpace: true
        )
        let window = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true,
            isKeyWindow: true,
            attachedSheet: sheet
        )

        XCTAssertEqual(SettingsWindowLifecycleCoordinator.toggleAction(for: window), .focus)
        XCTAssertFalse(SettingsWindowLifecycleCoordinator.isDismissibleSettingsWindow(window))
    }

    func testToggleSettingsShortcutHasNoDefaultShortcut() {
        XCTAssertNil(KeyboardShortcuts.Name.toggleSettings.defaultShortcut)
    }
}

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

    func testCoordinatorIdentifiesActiveSettingsWindow() {
        let window = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true,
            isKeyWindow: true
        )

        XCTAssertTrue(SettingsWindowLifecycleCoordinator.isActiveSettingsWindow(window))
        XCTAssertEqual(SettingsWindowLifecycleCoordinator.activationPolicy(for: window), .regular)
    }

    func testActivationPolicyFallsBackToAccessoryWhenSettingsWindowIsNotActive() {
        let backgroundWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        let nonSettingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("other"),
            isVisible: true,
            isOnActiveSpace: true,
            isKeyWindow: true
        )

        XCTAssertFalse(SettingsWindowLifecycleCoordinator.isActiveSettingsWindow(backgroundWindow))
        XCTAssertEqual(SettingsWindowLifecycleCoordinator.activationPolicy(for: backgroundWindow), .accessory)
        XCTAssertEqual(SettingsWindowLifecycleCoordinator.activationPolicy(for: nonSettingsWindow), .accessory)
        XCTAssertEqual(SettingsWindowLifecycleCoordinator.activationPolicy(for: nil), .accessory)
    }
}

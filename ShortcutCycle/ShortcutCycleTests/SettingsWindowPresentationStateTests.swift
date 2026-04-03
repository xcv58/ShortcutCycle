import AppKit
import XCTest
@testable import ShortcutCycle

@MainActor
final class SettingsWindowPresentationStateTests: XCTestCase {
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

@MainActor
private final class MockWindow: NSWindow {
    private let mockIsVisible: Bool
    private let mockIsOnActiveSpace: Bool

    init(
        identifier: NSUserInterfaceItemIdentifier?,
        isVisible: Bool,
        isOnActiveSpace: Bool
    ) {
        self.mockIsVisible = isVisible
        self.mockIsOnActiveSpace = isOnActiveSpace
        super.init(
            contentRect: .zero,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        self.identifier = identifier
    }

    override var isVisible: Bool {
        mockIsVisible
    }

    override var isOnActiveSpace: Bool {
        mockIsOnActiveSpace
    }
}

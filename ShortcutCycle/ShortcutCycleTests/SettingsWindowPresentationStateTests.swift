import AppKit
import XCTest
@testable import ShortcutCycle

@MainActor
final class SettingsWindowPresentationStateTests: XCTestCase {
    func testHUDPresentationUsesDeferredActivationForVisibleOffSpaceSettingsWindow() {
        XCTAssertTrue(
            SettingsWindowHUDPresentationPolicy.shouldUseDeferredActivation(
                windows: [
                    SettingsWindowSnapshot(
                        isSettingsWindow: true,
                        isVisible: true,
                        isOnActiveSpace: false
                    )
                ]
            )
        )
    }

    func testHUDPresentationDoesNotUseDeferredActivationForVisibleCurrentSpaceSettingsWindow() {
        XCTAssertFalse(
            SettingsWindowHUDPresentationPolicy.shouldUseDeferredActivation(
                windows: [
                    SettingsWindowSnapshot(
                        isSettingsWindow: true,
                        isVisible: true,
                        isOnActiveSpace: true
                    )
                ]
            )
        )
    }

    func testHUDPresentationDoesNotUseDeferredActivationForHiddenOrNonSettingsWindows() {
        XCTAssertFalse(
            SettingsWindowHUDPresentationPolicy.shouldUseDeferredActivation(
                windows: [
                    SettingsWindowSnapshot(
                        isSettingsWindow: true,
                        isVisible: false,
                        isOnActiveSpace: false
                    ),
                    SettingsWindowSnapshot(
                        isSettingsWindow: false,
                        isVisible: true,
                        isOnActiveSpace: false
                    )
                ]
            )
        )
    }

    func testDockReopenDependsOnlyOnVisibleWindows() {
        XCTAssertTrue(
            SettingsWindowHUDPresentationPolicy.shouldHandleDockReopen(
                hasVisibleWindows: false
            )
        )

        XCTAssertFalse(
            SettingsWindowHUDPresentationPolicy.shouldHandleDockReopen(
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

    func testCoordinatorDetectsOffSpaceSettingsWindowFromWindows() {
        let offSpaceSettingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: false
        )
        let currentSpaceSettingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )
        let nonSettingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("other"),
            isVisible: true,
            isOnActiveSpace: false
        )

        XCTAssertTrue(
            SettingsWindowLifecycleCoordinator.hasOffSpaceSettingsWindow(
                in: [offSpaceSettingsWindow]
            )
        )
        XCTAssertFalse(
            SettingsWindowLifecycleCoordinator.hasOffSpaceSettingsWindow(
                in: [currentSpaceSettingsWindow]
            )
        )
        XCTAssertFalse(
            SettingsWindowLifecycleCoordinator.hasOffSpaceSettingsWindow(
                in: [nonSettingsWindow]
            )
        )
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

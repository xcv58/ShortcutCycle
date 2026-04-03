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
}

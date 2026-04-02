import XCTest
@testable import ShortcutCycle

@MainActor
final class SettingsWindowPresentationStateTests: XCTestCase {
    func testTemporarilyHiddenWindowRestoresOnNextPresentation() {
        var state = SettingsWindowPresentationState()

        state.markTemporarilyHidden()
        let action = state.presentationActionForExistingWindow(isVisible: false)

        XCTAssertEqual(action, .restoreHiddenWindow)
        XCTAssertFalse(state.isTemporarilyHidden)
    }

    func testVisibleWindowUsesBringToFrontAction() {
        var state = SettingsWindowPresentationState()

        let action = state.presentationActionForExistingWindow(isVisible: true)

        XCTAssertEqual(action, .bringToFront)
        XCTAssertFalse(state.isTemporarilyHidden)
    }

    func testWindowCloseClearsTemporarilyHiddenState() {
        var state = SettingsWindowPresentationState()
        state.markTemporarilyHidden()

        state.windowDidClose()

        XCTAssertFalse(state.isTemporarilyHidden)
    }

    func testDockReopenHandlesHiddenSettingsWindow() {
        var state = SettingsWindowPresentationState()
        state.markTemporarilyHidden()

        XCTAssertTrue(state.shouldHandleDockReopen(hasVisibleWindows: true))
    }

    func testDockReopenHandlesAppWithoutVisibleWindows() {
        let state = SettingsWindowPresentationState()

        XCTAssertTrue(state.shouldHandleDockReopen(hasVisibleWindows: false))
    }
}

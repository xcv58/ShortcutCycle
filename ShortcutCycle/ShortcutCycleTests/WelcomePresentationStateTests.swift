import XCTest
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif
@testable import ShortcutCycle

@MainActor
final class WelcomePresentationStateTests: XCTestCase {
    func testConsumePendingRequestShowsCalloutAndTargetsGroupsTab() {
        let requestID = UUID()
        var state = WelcomePresentationState()

        let nextTab = state.consumePendingRequest(requestID)

        XCTAssertEqual(nextTab, URLSettingsTab.groups.rawValue)
        XCTAssertEqual(state.activeRequestID, requestID)
        XCTAssertTrue(state.isShowingCallout)
    }

    func testConsumePendingRequestIgnoresNil() {
        var state = WelcomePresentationState()

        let nextTab = state.consumePendingRequest(nil)

        XCTAssertNil(nextTab)
        XCTAssertNil(state.activeRequestID)
        XCTAssertFalse(state.isShowingCallout)
    }

    func testDismissClearsCurrentCallout() {
        var state = WelcomePresentationState()
        _ = state.consumePendingRequest(UUID())

        state.dismiss()

        XCTAssertNil(state.activeRequestID)
        XCTAssertFalse(state.isShowingCallout)
    }

    func testEndWindowSessionClearsCurrentCallout() {
        var state = WelcomePresentationState()
        _ = state.consumePendingRequest(UUID())

        state.endWindowSession()

        XCTAssertNil(state.activeRequestID)
        XCTAssertFalse(state.isShowingCallout)
    }

    func testNewRequestAfterDismissShowsCalloutAgain() {
        let firstRequest = UUID()
        let secondRequest = UUID()
        var state = WelcomePresentationState()

        _ = state.consumePendingRequest(firstRequest)
        state.dismiss()

        let nextTab = state.consumePendingRequest(secondRequest)

        XCTAssertEqual(nextTab, URLSettingsTab.groups.rawValue)
        XCTAssertEqual(state.activeRequestID, secondRequest)
        XCTAssertTrue(state.isShowingCallout)
    }
}

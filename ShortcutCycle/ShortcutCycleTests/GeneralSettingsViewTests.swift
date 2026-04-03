import XCTest
@testable import ShortcutCycle

@MainActor
final class GeneralSettingsViewTests: XCTestCase {
    func testSpaceJumpWarningTextShownWhenHUDEnabled() {
        XCTAssertEqual(
            GeneralSettingsView.spaceJumpWarningText(
                showHUD: true,
                language: "en"
            ),
            "If Settings is open on another Space, macOS may briefly switch Spaces while showing the HUD."
        )
    }

    func testSpaceJumpWarningTextHiddenWhenHUDDisabled() {
        XCTAssertNil(
            GeneralSettingsView.spaceJumpWarningText(
                showHUD: false,
                language: "en"
            )
        )
    }
}

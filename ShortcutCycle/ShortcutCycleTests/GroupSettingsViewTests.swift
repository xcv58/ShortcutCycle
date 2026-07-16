import XCTest
@testable import ShortcutCycle

@MainActor
final class GroupSettingsViewTests: XCTestCase {
    // Regression guard: GroupSettingsView must not require any welcome-coordinator
    // state (previously it held a WelcomeCoordinator reference that caused a
    // compile error once that type was removed).
    func testGroupSettingsViewCanBeConstructed() {
        _ = GroupSettingsView()
    }

    func testCustomShortcutRecorderRequiresAFunctionalModifier() {
        XCTAssertFalse(
            ShortcutRecorderInput.isRecordable(
                keyCode: 18,
                modifierFlags: [.shift]
            )
        )
        XCTAssertTrue(
            ShortcutRecorderInput.isRecordable(
                keyCode: 18,
                modifierFlags: [.option]
            )
        )
    }

    func testCustomShortcutRecorderTreatsDeleteAsClearOnlyWithoutModifiers() {
        XCTAssertTrue(
            ShortcutRecorderInput.isClearKey(
                51,
                modifierFlags: []
            )
        )
        XCTAssertFalse(
            ShortcutRecorderInput.isClearKey(
                51,
                modifierFlags: [.command]
            )
        )
    }
}

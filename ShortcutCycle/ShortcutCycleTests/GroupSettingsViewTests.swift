import Carbon.HIToolbox
import KeyboardShortcuts
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

    func testCustomShortcutRecorderAllowsFunctionKeysWithoutModifiers() {
        XCTAssertTrue(
            ShortcutRecorderInput.isRecordable(
                keyCode: UInt16(kVK_F1),
                modifierFlags: []
            )
        )
        XCTAssertFalse(
            ShortcutRecorderInput.requiresModifier(
                keyCode: UInt16(kVK_F1),
                modifierFlags: []
            )
        )
        XCTAssertTrue(
            ShortcutRecorderInput.requiresModifier(
                keyCode: 0,
                modifierFlags: []
            )
        )
    }

    func testCustomShortcutRecorderFormatsModifiersAndKeyWithSeparators() {
        let shortcut = KeyboardShortcuts.Shortcut(.x, modifiers: [.shift, .command])

        XCTAssertEqual(
            ShortcutRecorderDisplay.formattedShortcut(shortcut),
            "⇧ + ⌘ + X"
        )
    }

    func testCustomShortcutRecorderFormatsModifierPreviewWithSeparators() {
        XCTAssertEqual(
            ShortcutRecorderDisplay.formattedModifierPreview([.control, .shift, .command]),
            "⌃ + ⇧ + ⌘"
        )
    }
}

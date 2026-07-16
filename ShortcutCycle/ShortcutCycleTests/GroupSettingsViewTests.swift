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

    func testCustomShortcutRecorderFormatsArrowKeyWithSeparators() {
        let shortcut = KeyboardShortcuts.Shortcut(.upArrow, modifiers: [.control, .command])

        XCTAssertEqual(
            ShortcutRecorderDisplay.formattedShortcut(shortcut),
            "⌃ + ⌘ + ↑"
        )
    }

    func testCustomShortcutRecorderFormatsFunctionKeyWithoutModifiers() {
        let shortcut = KeyboardShortcuts.Shortcut(.f1)

        XCTAssertEqual(
            ShortcutRecorderDisplay.formattedShortcut(shortcut),
            "F1"
        )
    }

    func testCustomShortcutRecorderFormatsModifierPreviewWithSeparators() {
        XCTAssertEqual(
            ShortcutRecorderDisplay.formattedModifierPreview([.control, .shift, .command]),
            "⌃ + ⇧ + ⌘"
        )
    }

    func testRecorderOnlyConsumesKeyboardEvents() {
        XCTAssertTrue(ShortcutRecorderSessionPolicy.monitoredEventTypes.contains(.keyDown))
        XCTAssertTrue(ShortcutRecorderSessionPolicy.monitoredEventTypes.contains(.flagsChanged))
        XCTAssertFalse(ShortcutRecorderSessionPolicy.monitoredEventTypes.contains(.leftMouseDown))
        XCTAssertFalse(ShortcutRecorderSessionPolicy.monitoredEventTypes.contains(.scrollWheel))
    }

    func testRecorderCancelsWhenItsWindowLosesFocusOrCloses() {
        XCTAssertEqual(
            ShortcutRecorderSessionPolicy.cancelingWindowNotifications,
            [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification]
        )
    }

    func testShortcutRecordingSuspensionWaitsForEveryActiveRecorder() {
        let manager = ShortcutManager.shared
        let originalState = KeyboardShortcuts.isEnabled
        defer {
            manager.resumeAfterShortcutRecording()
            manager.resumeAfterShortcutRecording()
            KeyboardShortcuts.isEnabled = originalState
        }

        KeyboardShortcuts.isEnabled = true
        manager.suspendForShortcutRecording()
        manager.suspendForShortcutRecording()

        XCTAssertFalse(KeyboardShortcuts.isEnabled)

        manager.resumeAfterShortcutRecording()
        XCTAssertFalse(KeyboardShortcuts.isEnabled)

        manager.resumeAfterShortcutRecording()
        XCTAssertTrue(KeyboardShortcuts.isEnabled)

        manager.resumeAfterShortcutRecording()
        XCTAssertTrue(KeyboardShortcuts.isEnabled)
    }

    func testShortcutRecordingSuspensionPreservesAnExistingDisabledState() {
        let manager = ShortcutManager.shared
        let originalState = KeyboardShortcuts.isEnabled
        defer {
            manager.resumeAfterShortcutRecording()
            KeyboardShortcuts.isEnabled = originalState
        }

        KeyboardShortcuts.isEnabled = false
        manager.suspendForShortcutRecording()
        manager.resumeAfterShortcutRecording()

        XCTAssertFalse(KeyboardShortcuts.isEnabled)
    }
}

import Carbon.HIToolbox
import KeyboardShortcuts
import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#endif
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
        XCTAssertFalse(
            ShortcutRecorderInput.isRecordable(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.function]
            )
        )
        XCTAssertFalse(
            ShortcutRecorderInput.isRecordable(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.shift, .function]
            )
        )
        XCTAssertTrue(
            ShortcutRecorderInput.requiresModifier(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.function]
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
        for keyCode in [kVK_F13, kVK_F20] {
            XCTAssertTrue(
                ShortcutRecorderInput.isRecordable(
                    keyCode: UInt16(keyCode),
                    modifierFlags: []
                )
            )
            XCTAssertFalse(
                ShortcutRecorderInput.requiresModifier(
                    keyCode: UInt16(keyCode),
                    modifierFlags: []
                )
            )
        }
    }

    func testShortcutReservationDetectsNestedAppMenuCommand() {
        let menu = NSMenu()
        let appItem = NSMenuItem(title: "App", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let shortcut = KeyboardShortcuts.Shortcut(.q, modifiers: [.command])
        let conflict = ShortcutReservationValidator.conflict(
            for: shortcut,
            context: reservationContext(mainMenu: menu)
        )

        XCTAssertEqual(conflict?.owner, .appCommand(titleKey: "Quit"))
    }

    func testShortcutReservationNormalizesUppercaseShiftedMenuCommand() {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Special", action: nil, keyEquivalent: "Q")
        item.keyEquivalentModifierMask = [.command]
        menu.addItem(item)

        let shortcut = KeyboardShortcuts.Shortcut(.q, modifiers: [.command, .shift])
        let conflict = ShortcutReservationValidator.conflict(
            for: shortcut,
            context: reservationContext(mainMenu: menu)
        )

        XCTAssertEqual(conflict?.owner, .appCommand(titleKey: "Special"))
    }

    func testShortcutReservationDetectsInjectedSystemShortcutExceptF12() {
        let systemShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command])
        let f12 = KeyboardShortcuts.Shortcut(.f12)
        let context = reservationContext(systemShortcuts: [systemShortcut, f12])

        XCTAssertEqual(
            ShortcutReservationValidator.conflict(for: systemShortcut, context: context)?.owner,
            .appCommand(titleKey: "macOS")
        )
        XCTAssertNil(ShortcutReservationValidator.conflict(for: f12, context: context))
    }

    func testShortcutReservationRejectsOptionOnlyShortcutOnAffectedSandboxedMacOS() {
        let shortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.option, .shift])
        let context = reservationContext(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 15,
                minorVersion: 1,
                patchVersion: 0
            ),
            isSandboxed: true
        )

        XCTAssertEqual(
            ShortcutReservationValidator.conflict(for: shortcut, context: context)?.owner,
            .appCommand(titleKey: "macOS")
        )
    }

    func testShortcutReservationAllowsOptionShortcutOutsideAffectedEnvironment() {
        let shortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.option])

        XCTAssertNil(
            ShortcutReservationValidator.conflict(
                for: shortcut,
                context: reservationContext(isSandboxed: false)
            )
        )
    }

    func testShortcutReservationFiltersAndBackfillsSuggestions() {
        let menu = NSMenu()
        let menuShortcut = KeyboardShortcuts.Shortcut(.two, modifiers: [.option])
        let menuItem = NSMenuItem(title: "Menu Two", action: nil, keyEquivalent: "2")
        menuItem.keyEquivalentModifierMask = [.option]
        menu.addItem(menuItem)

        let systemShortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.option])
        let available = KeyboardShortcuts.Shortcut(.three, modifiers: [.option])
        let nextAvailable = KeyboardShortcuts.Shortcut(.four, modifiers: [.option])
        let context = reservationContext(
            mainMenu: menu,
            systemShortcuts: [systemShortcut]
        )

        XCTAssertEqual(
            ShortcutReservationValidator.availableShortcuts(
                from: [systemShortcut, menuShortcut, available, nextAvailable],
                limit: 2,
                context: context
            ),
            [available, nextAvailable]
        )
        XCTAssertEqual(
            ShortcutReservationValidator.availableShortcuts(
                from: [available],
                limit: 0,
                context: context
            ),
            []
        )
    }

    func testImportedGroupShortcutChecksSettingsWindowReservation() {
        let shortcut = KeyboardShortcuts.Shortcut(.f20)
        let group = AppGroup(name: "Imported")
        KeyboardShortcuts.setShortcut(shortcut, for: .toggleSettings)
        defer { KeyboardShortcuts.setShortcut(nil, for: .toggleSettings) }

        let rejection = ShortcutReservationValidator.importRejection(
            for: shortcut,
            assigning: .group(id: group.id, name: group.name)
        )

        XCTAssertEqual(
            rejection,
            .conflict(
                ShortcutAssignmentConflict(
                    shortcut: shortcut,
                    owner: .settingsWindow
                )
            )
        )
    }

    func testCustomShortcutRecorderFormatsModifiersAndKeyWithSeparators() {
        let shortcut = KeyboardShortcuts.Shortcut(.x, modifiers: [.shift, .command])

        XCTAssertEqual(
            ShortcutDisplayFormatter.formattedShortcut(shortcut),
            "⇧ + ⌘ + X"
        )
    }

    func testCustomShortcutRecorderFormatsArrowKeyWithSeparators() {
        let shortcut = KeyboardShortcuts.Shortcut(.upArrow, modifiers: [.control, .command])

        XCTAssertEqual(
            ShortcutDisplayFormatter.formattedShortcut(shortcut),
            "⌃ + ⌘ + ↑"
        )
    }

    func testCustomShortcutRecorderFormatsFunctionKeyWithoutModifiers() {
        let shortcut = KeyboardShortcuts.Shortcut(.f1)

        XCTAssertEqual(
            ShortcutDisplayFormatter.formattedShortcut(shortcut),
            "F1"
        )
    }

    func testShortcutSuggestionUsesPlusSeparatedRecorderFormatting() {
        let shortcut = KeyboardShortcuts.Shortcut(.five, modifiers: [.option])

        XCTAssertEqual(
            ShortcutDisplayFormatter.formattedShortcut(shortcut),
            "⌥ + 5"
        )
    }

    func testCustomShortcutRecorderFormatsModifierPreviewWithSeparators() {
        XCTAssertEqual(
            ShortcutDisplayFormatter.formattedModifierPreview([.control, .shift, .command]),
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

    private func reservationContext(
        mainMenu: NSMenu? = nil,
        systemShortcuts: Set<KeyboardShortcuts.Shortcut> = [],
        operatingSystemVersion: OperatingSystemVersion = OperatingSystemVersion(
            majorVersion: 14,
            minorVersion: 0,
            patchVersion: 0
        ),
        isSandboxed: Bool = false
    ) -> ShortcutReservationValidator.Context {
        ShortcutReservationValidator.Context(
            mainMenu: mainMenu,
            systemShortcuts: systemShortcuts,
            operatingSystemVersion: operatingSystemVersion,
            isSandboxed: isSandboxed
        )
    }
}

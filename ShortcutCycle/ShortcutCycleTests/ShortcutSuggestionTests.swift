import XCTest
import KeyboardShortcuts
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

final class ShortcutSuggestionTests: XCTestCase {

    @MainActor
    func testAvailableReturnsDeterministicFirstThreeUnusedOptionNumberShortcuts() {
        let previousSettingsShortcut = KeyboardShortcuts.getShortcut(for: .toggleSettings)
        let excludedGroup = AppGroup(id: UUID(), name: "Excluded")
        let assignedGroups = [
            AppGroup(id: UUID(), name: "First"),
            AppGroup(id: UUID(), name: "Second"),
            AppGroup(id: UUID(), name: "Third")
        ]

        KeyboardShortcuts.setShortcut(nil, for: .toggleSettings)
        KeyboardShortcuts.setShortcut(.init(.one, modifiers: [.option]), for: excludedGroup.shortcutName)
        KeyboardShortcuts.setShortcut(.init(.two, modifiers: [.option]), for: assignedGroups[0].shortcutName)
        KeyboardShortcuts.setShortcut(.init(.three, modifiers: [.option]), for: assignedGroups[1].shortcutName)
        KeyboardShortcuts.setShortcut(.init(.four, modifiers: [.option]), for: assignedGroups[2].shortcutName)

        defer {
            KeyboardShortcuts.setShortcut(previousSettingsShortcut, for: .toggleSettings)
            KeyboardShortcuts.setShortcut(nil, for: excludedGroup.shortcutName)
            assignedGroups.forEach { group in
                KeyboardShortcuts.setShortcut(nil, for: group.shortcutName)
            }
        }

        let expected: [KeyboardShortcuts.Shortcut] = [
            .init(.one, modifiers: [.option]),
            .init(.five, modifiers: [.option]),
            .init(.six, modifiers: [.option])
        ]
        let suggestions = ShortcutSuggestions.available(
            for: [excludedGroup] + assignedGroups,
            excluding: excludedGroup.id
        )

        XCTAssertEqual(suggestions, expected)
    }

    @MainActor
    func testAvailableReturnsFewerThanLimitWhenNotEnoughCandidatesRemain() {
        let previousSettingsShortcut = KeyboardShortcuts.getShortcut(for: .toggleSettings)
        let optionKeys: [KeyboardShortcuts.Key] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
        let groups = (1...9).map { index in
            AppGroup(id: UUID(), name: "Group \(index)")
        }

        KeyboardShortcuts.setShortcut(nil, for: .toggleSettings)
        for (index, group) in groups.enumerated() {
            KeyboardShortcuts.setShortcut(.init(optionKeys[index], modifiers: [.option]), for: group.shortcutName)
        }

        defer {
            KeyboardShortcuts.setShortcut(previousSettingsShortcut, for: .toggleSettings)
            groups.forEach { group in
                KeyboardShortcuts.setShortcut(nil, for: group.shortcutName)
            }
        }

        let expected: [KeyboardShortcuts.Shortcut] = [
            .init(.one, modifiers: [.option]),
        ]
        let suggestions = ShortcutSuggestions.available(
            for: groups,
            excluding: groups[0].id
        )

        XCTAssertEqual(suggestions, expected)
    }

    @MainActor
    func testAvailableExcludesSettingsWindowShortcut() {
        let previousSettingsShortcut = KeyboardShortcuts.getShortcut(for: .toggleSettings)
        let group = AppGroup(id: UUID(), name: "Target")
        KeyboardShortcuts.setShortcut(.init(.one, modifiers: [.option]), for: .toggleSettings)

        defer {
            KeyboardShortcuts.setShortcut(previousSettingsShortcut, for: .toggleSettings)
            KeyboardShortcuts.setShortcut(nil, for: group.shortcutName)
        }

        let expected: [KeyboardShortcuts.Shortcut] = [
            .init(.two, modifiers: [.option]),
            .init(.three, modifiers: [.option]),
            .init(.four, modifiers: [.option])
        ]
        let suggestions = ShortcutSuggestions.available(for: [group], excluding: group.id)

        XCTAssertEqual(suggestions, expected)
    }

    @MainActor
    func testConflictDetectsSettingsWindowShortcutWhenAssigningGroupShortcut() {
        let previousSettingsShortcut = KeyboardShortcuts.getShortcut(for: .toggleSettings)
        let group = AppGroup(id: UUID(), name: "Work")
        let shortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.option])
        KeyboardShortcuts.setShortcut(shortcut, for: .toggleSettings)

        defer {
            KeyboardShortcuts.setShortcut(previousSettingsShortcut, for: .toggleSettings)
            KeyboardShortcuts.setShortcut(nil, for: group.shortcutName)
        }

        let conflict = ShortcutAssignmentConflicts.conflict(
            for: shortcut,
            assigning: .group(id: group.id, name: group.name),
            groups: [group]
        )

        XCTAssertEqual(conflict?.shortcut, shortcut)
        XCTAssertEqual(conflict?.owner, .settingsWindow)
    }

    @MainActor
    func testConflictDetectsGroupShortcutWhenAssigningSettingsWindowShortcut() {
        let previousSettingsShortcut = KeyboardShortcuts.getShortcut(for: .toggleSettings)
        let group = AppGroup(id: UUID(), name: "Work")
        let shortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.option])
        KeyboardShortcuts.setShortcut(nil, for: .toggleSettings)
        KeyboardShortcuts.setShortcut(shortcut, for: group.shortcutName)

        defer {
            KeyboardShortcuts.setShortcut(previousSettingsShortcut, for: .toggleSettings)
            KeyboardShortcuts.setShortcut(nil, for: group.shortcutName)
        }

        let conflict = ShortcutAssignmentConflicts.conflict(
            for: shortcut,
            assigning: .settingsWindow,
            groups: [group]
        )

        XCTAssertEqual(conflict?.shortcut, shortcut)
        XCTAssertEqual(conflict?.owner, .group(id: group.id, name: group.name))
    }

    @MainActor
    func testConflictDetectsOtherGroupShortcutWhenAssigningGroupShortcut() {
        let previousSettingsShortcut = KeyboardShortcuts.getShortcut(for: .toggleSettings)
        let targetGroup = AppGroup(id: UUID(), name: "Target")
        let existingGroup = AppGroup(id: UUID(), name: "Existing")
        let shortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.option])
        KeyboardShortcuts.setShortcut(nil, for: .toggleSettings)
        KeyboardShortcuts.setShortcut(shortcut, for: existingGroup.shortcutName)

        defer {
            KeyboardShortcuts.setShortcut(previousSettingsShortcut, for: .toggleSettings)
            KeyboardShortcuts.setShortcut(nil, for: targetGroup.shortcutName)
            KeyboardShortcuts.setShortcut(nil, for: existingGroup.shortcutName)
        }

        let conflict = ShortcutAssignmentConflicts.conflict(
            for: shortcut,
            assigning: .group(id: targetGroup.id, name: targetGroup.name),
            groups: [targetGroup, existingGroup]
        )

        XCTAssertEqual(conflict?.shortcut, shortcut)
        XCTAssertEqual(conflict?.owner, .group(id: existingGroup.id, name: existingGroup.name))
    }

    @MainActor
    func testConflictDetectsAppCommandShortcutWhenAssigningShortcut() {
        let previousSettingsShortcut = KeyboardShortcuts.getShortcut(for: .toggleSettings)
        let group = AppGroup(id: UUID(), name: "Target")
        let shortcut = KeyboardShortcuts.Shortcut(.downArrow, modifiers: [.command])
        KeyboardShortcuts.setShortcut(nil, for: .toggleSettings)

        defer {
            KeyboardShortcuts.setShortcut(previousSettingsShortcut, for: .toggleSettings)
            KeyboardShortcuts.setShortcut(nil, for: group.shortcutName)
        }

        let conflict = ShortcutAssignmentConflicts.conflict(
            for: shortcut,
            assigning: .group(id: group.id, name: group.name),
            groups: [group]
        )

        XCTAssertEqual(conflict?.shortcut, shortcut)
        XCTAssertEqual(conflict?.owner, .appCommand(titleKey: "Next Group"))
        XCTAssertEqual(conflict?.owner.displayName { $0 == "Next Group" ? "下一个群组" : $0 }, "下一个群组")
    }

    @MainActor
    func testConflictIgnoresAssignedGroupShortcut() {
        let previousSettingsShortcut = KeyboardShortcuts.getShortcut(for: .toggleSettings)
        let group = AppGroup(id: UUID(), name: "Work")
        let shortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.option])
        KeyboardShortcuts.setShortcut(nil, for: .toggleSettings)
        KeyboardShortcuts.setShortcut(shortcut, for: group.shortcutName)

        defer {
            KeyboardShortcuts.setShortcut(previousSettingsShortcut, for: .toggleSettings)
            KeyboardShortcuts.setShortcut(nil, for: group.shortcutName)
        }

        let conflict = ShortcutAssignmentConflicts.conflict(
            for: shortcut,
            assigning: .group(id: group.id, name: group.name),
            groups: [group]
        )

        XCTAssertNil(conflict)
    }
}

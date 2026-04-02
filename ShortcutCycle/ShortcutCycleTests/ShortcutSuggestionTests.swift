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
        let excludedGroup = AppGroup(id: UUID(), name: "Excluded")
        let assignedGroups = [
            AppGroup(id: UUID(), name: "First"),
            AppGroup(id: UUID(), name: "Second"),
            AppGroup(id: UUID(), name: "Third")
        ]

        KeyboardShortcuts.setShortcut(.init(.one, modifiers: [.option]), for: excludedGroup.shortcutName)
        KeyboardShortcuts.setShortcut(.init(.two, modifiers: [.option]), for: assignedGroups[0].shortcutName)
        KeyboardShortcuts.setShortcut(.init(.three, modifiers: [.option]), for: assignedGroups[1].shortcutName)
        KeyboardShortcuts.setShortcut(.init(.four, modifiers: [.option]), for: assignedGroups[2].shortcutName)

        defer {
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
        let optionKeys: [KeyboardShortcuts.Key] = [.one, .two, .three, .four, .five, .six, .seven]
        let groups = (1...7).map { index in
            AppGroup(id: UUID(), name: "Group \(index)")
        }

        for (index, group) in groups.enumerated() {
            KeyboardShortcuts.setShortcut(.init(optionKeys[index], modifiers: [.option]), for: group.shortcutName)
        }

        defer {
            groups.forEach { group in
                KeyboardShortcuts.setShortcut(nil, for: group.shortcutName)
            }
        }

        let expected: [KeyboardShortcuts.Shortcut] = [
            .init(.one, modifiers: [.option]),
            .init(.eight, modifiers: [.option]),
            .init(.nine, modifiers: [.option])
        ]
        let suggestions = ShortcutSuggestions.available(
            for: groups,
            excluding: groups[0].id
        )

        XCTAssertEqual(suggestions, expected)
    }
}

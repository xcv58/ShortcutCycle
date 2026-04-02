import Foundation
import KeyboardShortcuts

public enum ShortcutSuggestions {
    @MainActor
    public static func available(
        for groups: [AppGroup],
        excluding groupID: UUID,
        limit: Int = 3
    ) -> [KeyboardShortcuts.Shortcut] {
        guard limit > 0 else { return [] }

        let candidates: [KeyboardShortcuts.Shortcut] = [
            .init(.one, modifiers: [.option]),
            .init(.two, modifiers: [.option]),
            .init(.three, modifiers: [.option]),
            .init(.four, modifiers: [.option]),
            .init(.five, modifiers: [.option]),
            .init(.six, modifiers: [.option]),
            .init(.seven, modifiers: [.option]),
            .init(.eight, modifiers: [.option]),
            .init(.nine, modifiers: [.option])
        ]

        let takenShortcuts = groups.compactMap { group -> KeyboardShortcuts.Shortcut? in
            guard group.id != groupID else { return nil }
            return KeyboardShortcuts.getShortcut(for: group.shortcutName)
        }

        return candidates
            .filter { candidate in !takenShortcuts.contains(candidate) }
            .prefix(limit)
            .map { $0 }
    }
}

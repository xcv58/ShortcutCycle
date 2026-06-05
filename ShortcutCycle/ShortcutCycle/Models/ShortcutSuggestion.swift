import AppKit
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

        var takenShortcuts = groups.compactMap { group -> KeyboardShortcuts.Shortcut? in
            guard group.id != groupID else { return nil }
            return KeyboardShortcuts.getShortcut(for: group.shortcutName)
        }
        if let settingsShortcut = KeyboardShortcuts.getShortcut(for: .toggleSettings) {
            takenShortcuts.append(settingsShortcut)
        }

        return candidates
            .filter { candidate in !takenShortcuts.contains(candidate) }
            .prefix(limit)
            .map { $0 }
    }
}

enum ShortcutAssignmentOwner: Equatable {
    case settingsWindow
    case group(id: UUID, name: String)

    static func == (lhs: ShortcutAssignmentOwner, rhs: ShortcutAssignmentOwner) -> Bool {
        switch (lhs, rhs) {
        case (.settingsWindow, .settingsWindow):
            return true
        case let (.group(lhsID, _), .group(rhsID, _)):
            return lhsID == rhsID
        default:
            return false
        }
    }

    var identifier: String {
        switch self {
        case .settingsWindow:
            return "settingsWindow"
        case let .group(id, _):
            return "group-\(id.uuidString)"
        }
    }

    func displayName(language: String) -> String {
        switch self {
        case .settingsWindow:
            return "Settings Window".localized(language: language)
        case let .group(_, name):
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? "Group Name".localized(language: language) : trimmedName
        }
    }
}

struct ShortcutAssignmentConflict: Equatable, Identifiable {
    let shortcut: KeyboardShortcuts.Shortcut
    let owner: ShortcutAssignmentOwner

    var id: String {
        "\(shortcut.carbonKeyCode)-\(shortcut.carbonModifiers)-\(owner.identifier)"
    }

    @MainActor
    func message(language: String) -> String {
        let conflictMessage = String(
            format: "The shortcut %@ is already used by %@.".localized(language: language),
            shortcut.description,
            owner.displayName(language: language)
        )
        let guidance = "Choose a different shortcut to avoid triggering both actions.".localized(language: language)
        return "\(conflictMessage)\n\n\(guidance)"
    }
}

enum ShortcutAssignmentConflicts {
    @MainActor
    static func conflict(
        for shortcut: KeyboardShortcuts.Shortcut?,
        assigning owner: ShortcutAssignmentOwner,
        groups: [AppGroup]
    ) -> ShortcutAssignmentConflict? {
        guard let shortcut else {
            return nil
        }

        if owner != .settingsWindow,
           KeyboardShortcuts.getShortcut(for: .toggleSettings) == shortcut {
            return ShortcutAssignmentConflict(shortcut: shortcut, owner: .settingsWindow)
        }

        for group in groups where owner != .group(id: group.id, name: group.name) {
            guard KeyboardShortcuts.getShortcut(for: group.shortcutName) == shortcut else {
                continue
            }
            return ShortcutAssignmentConflict(
                shortcut: shortcut,
                owner: .group(id: group.id, name: group.name)
            )
        }

        return nil
    }
}

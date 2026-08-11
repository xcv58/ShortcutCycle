import AppKit
import Foundation
import KeyboardShortcuts

/// Produces the app's user-facing shortcut notation, with each keyboard
/// component separated consistently (for example, `⌥ + ⇧ + A`).
@MainActor
public enum ShortcutDisplayFormatter {
    public static func formattedShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> String {
        let modifierSymbols = shortcut.modifiers.ks_symbolicRepresentation

        // KeyboardShortcuts defines `description` as this same modifier prefix
        // followed by its presentable key label. Keep tests for ordinary and
        // special keys so an upstream representation change is caught early.
        let key = String(shortcut.description.dropFirst(modifierSymbols.count))
        return components(modifiers: modifierSymbols, key: key)
    }

    public static func formattedModifierPreview(_ modifiers: NSEvent.ModifierFlags) -> String {
        components(modifiers: modifiers.ks_symbolicRepresentation, key: nil)
    }

    private static func components(modifiers: String, key: String?) -> String {
        var components = modifiers.map(String.init)

        if let key, !key.isEmpty {
            components.append(key)
        }

        return components.joined(separator: " + ")
    }
}

public enum ShortcutAssignmentRejection: Equatable, Identifiable {
    case conflict(ShortcutAssignmentConflict)
    case requiresModifier
    case invalidShortcut

    public var id: String {
        switch self {
        case .conflict(let conflict):
            return "conflict-\(conflict.id)"
        case .requiresModifier:
            return "requiresModifier"
        case .invalidShortcut:
            return "invalidShortcut"
        }
    }

    @MainActor
    public func title(localize: (String) -> String) -> String {
        switch self {
        case .conflict:
            return localize("Shortcut Already Used")
        case .requiresModifier, .invalidShortcut:
            return localize("Keyboard Shortcut")
        }
    }

    @MainActor
    public func message(localize: (String) -> String) -> String {
        switch self {
        case .conflict(let conflict):
            return conflict.message(localize: localize)
        case .requiresModifier:
            return localize("Shortcut must include a modifier key.")
        case .invalidShortcut:
            return localize("The shortcut is invalid.")
        }
    }
}

/// Shared semantic policy for every shortcut assignment path.
public enum ShortcutAssignmentEligibility {
    private static let carbonKeyCodeRange = 0...127
    private static let qualifyingModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option
    ]
    private static let modifierKeyCodes: Set<Int> = [
        KeyboardShortcuts.Key.command.rawValue,
        KeyboardShortcuts.Key.rightCommand.rawValue,
        KeyboardShortcuts.Key.control.rawValue,
        KeyboardShortcuts.Key.rightControl.rawValue,
        KeyboardShortcuts.Key.option.rawValue,
        KeyboardShortcuts.Key.rightOption.rawValue,
        KeyboardShortcuts.Key.shift.rawValue,
        KeyboardShortcuts.Key.rightShift.rawValue,
        KeyboardShortcuts.Key.capsLock.rawValue,
        KeyboardShortcuts.Key.function.rawValue
    ]
    private static let functionKeyCodes: Set<Int> = [
        KeyboardShortcuts.Key.f1.rawValue,
        KeyboardShortcuts.Key.f2.rawValue,
        KeyboardShortcuts.Key.f3.rawValue,
        KeyboardShortcuts.Key.f4.rawValue,
        KeyboardShortcuts.Key.f5.rawValue,
        KeyboardShortcuts.Key.f6.rawValue,
        KeyboardShortcuts.Key.f7.rawValue,
        KeyboardShortcuts.Key.f8.rawValue,
        KeyboardShortcuts.Key.f9.rawValue,
        KeyboardShortcuts.Key.f10.rawValue,
        KeyboardShortcuts.Key.f11.rawValue,
        KeyboardShortcuts.Key.f12.rawValue,
        KeyboardShortcuts.Key.f13.rawValue,
        KeyboardShortcuts.Key.f14.rawValue,
        KeyboardShortcuts.Key.f15.rawValue,
        KeyboardShortcuts.Key.f16.rawValue,
        KeyboardShortcuts.Key.f17.rawValue,
        KeyboardShortcuts.Key.f18.rawValue,
        KeyboardShortcuts.Key.f19.rawValue,
        KeyboardShortcuts.Key.f20.rawValue
    ]
    private static let supportedCarbonModifierMask = KeyboardShortcuts.Shortcut(
        .a,
        modifiers: [.command, .control, .option, .shift, .function]
    ).carbonModifiers

    public static func rejection(
        keyCode: Int,
        modifierFlags: NSEvent.ModifierFlags
    ) -> ShortcutAssignmentRejection? {
        guard carbonKeyCodeRange.contains(keyCode), !modifierKeyCodes.contains(keyCode) else {
            return .invalidShortcut
        }

        if functionKeyCodes.contains(keyCode) {
            return nil
        }

        let normalizedModifiers = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad])
        guard !normalizedModifiers.intersection(qualifyingModifiers).isEmpty else {
            return .requiresModifier
        }

        return nil
    }

    public static func rejection(
        for shortcut: KeyboardShortcuts.Shortcut
    ) -> ShortcutAssignmentRejection? {
        rejection(
            keyCode: shortcut.carbonKeyCode,
            modifierFlags: shortcut.modifiers
        )
    }

    public static func rawDataRejection(
        for data: ShortcutData
    ) -> ShortcutAssignmentRejection? {
        guard
            carbonKeyCodeRange.contains(data.carbonKeyCode),
            data.carbonModifiers >= 0,
            data.carbonModifiers & ~supportedCarbonModifierMask == 0
        else {
            return .invalidShortcut
        }

        return nil
    }

    public static func rejection(for data: ShortcutData) -> ShortcutAssignmentRejection? {
        if let rejection = rawDataRejection(for: data) {
            return rejection
        }

        return rejection(for: data.shortcut)
    }
}

public enum ShortcutSuggestions {
    @MainActor
    public static func available(
        for groups: [AppGroup],
        excluding groupID: UUID,
        recentShortcuts: [KeyboardShortcuts.Shortcut] = [],
        currentShortcut: KeyboardShortcuts.Shortcut? = nil,
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

        if let currentShortcut {
            takenShortcuts.append(currentShortcut)
        }

        func isAvailable(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
            ShortcutAssignmentEligibility.rejection(for: shortcut) == nil
                && !takenShortcuts.contains(shortcut)
                && AppCommandShortcutConflicts.conflict(for: shortcut) == nil
        }

        var suggestions: [KeyboardShortcuts.Shortcut] = []

        for shortcut in recentShortcuts where isAvailable(shortcut) {
            guard !suggestions.contains(shortcut) else { continue }
            suggestions.append(shortcut)
            guard suggestions.count < limit else { return suggestions }
        }

        for shortcut in candidates where isAvailable(shortcut) {
            guard !suggestions.contains(shortcut) else { continue }
            suggestions.append(shortcut)
            guard suggestions.count < limit else { break }
        }

        return suggestions
    }
}

public enum ShortcutAssignmentOwner: Equatable {
    case settingsWindow
    case group(id: UUID, name: String)
    case appCommand(titleKey: String)

    public static func == (lhs: ShortcutAssignmentOwner, rhs: ShortcutAssignmentOwner) -> Bool {
        switch (lhs, rhs) {
        case (.settingsWindow, .settingsWindow):
            return true
        case let (.group(lhsID, _), .group(rhsID, _)):
            return lhsID == rhsID
        case let (.appCommand(lhsTitle), .appCommand(rhsTitle)):
            return lhsTitle == rhsTitle
        default:
            return false
        }
    }

    fileprivate var identifier: String {
        switch self {
        case .settingsWindow:
            return "settingsWindow"
        case let .group(id, _):
            return "group-\(id.uuidString)"
        case let .appCommand(titleKey):
            return "appCommand-\(titleKey)"
        }
    }

    public func displayName(localize: (String) -> String) -> String {
        switch self {
        case .settingsWindow:
            return localize("Settings Window")
        case let .group(_, name):
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? localize("Group Name") : trimmedName
        case let .appCommand(titleKey):
            return localize(titleKey)
        }
    }
}

public struct ShortcutAssignmentConflict: Equatable, Identifiable {
    public let shortcut: KeyboardShortcuts.Shortcut
    public let owner: ShortcutAssignmentOwner

    public init(
        shortcut: KeyboardShortcuts.Shortcut,
        owner: ShortcutAssignmentOwner
    ) {
        self.shortcut = shortcut
        self.owner = owner
    }

    public var id: String {
        "\(shortcut.carbonKeyCode)-\(shortcut.carbonModifiers)-\(owner.identifier)"
    }

    @MainActor
    public func message(localize: (String) -> String) -> String {
        let conflictMessage = String(
            format: localize("The shortcut %@ is already used by %@."),
            ShortcutDisplayFormatter.formattedShortcut(shortcut),
            owner.displayName(localize: localize)
        )
        let guidance = localize("Choose a different shortcut to avoid triggering both actions.")
        return "\(conflictMessage)\n\n\(guidance)"
    }
}

public enum ShortcutAssignmentConflicts {
    @MainActor
    public static func conflict(
        for shortcut: KeyboardShortcuts.Shortcut?,
        assigning owner: ShortcutAssignmentOwner,
        groups: [AppGroup]
    ) -> ShortcutAssignmentConflict? {
        guard let shortcut else {
            return nil
        }

        if let conflict = AppCommandShortcutConflicts.conflict(for: shortcut) {
            return conflict
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

enum AppCommandShortcutConflicts {
    private struct AppCommandShortcut {
        let titleKey: String
        let shortcut: KeyboardShortcuts.Shortcut
    }

    private static let shortcuts: [AppCommandShortcut] = [
        .init(titleKey: "Settings...", shortcut: .init(.comma, modifiers: [.command])),
        .init(titleKey: "Add Group", shortcut: .init(.n, modifiers: [.command])),
        .init(titleKey: "Delete Group", shortcut: .init(.delete, modifiers: [.command])),
        .init(titleKey: "Toggle Sidebar", shortcut: .init(.s, modifiers: [.command, .control])),
        .init(titleKey: "Toggle Appearance", shortcut: .init(.a, modifiers: [.command, .control])),
        .init(titleKey: "Groups", shortcut: .init(.one, modifiers: [.command])),
        .init(titleKey: "General", shortcut: .init(.two, modifiers: [.command])),
        .init(titleKey: "Previous Group", shortcut: .init(.upArrow, modifiers: [.command])),
        .init(titleKey: "Next Group", shortcut: .init(.downArrow, modifiers: [.command])),
        .init(titleKey: "Previous Group", shortcut: .init(.leftBracket, modifiers: [.command])),
        .init(titleKey: "Next Group", shortcut: .init(.rightBracket, modifiers: [.command])),
        .init(titleKey: "Previous Group", shortcut: .init(.k, modifiers: [.command])),
        .init(titleKey: "Next Group", shortcut: .init(.j, modifiers: [.command])),
        .init(titleKey: "Move Group Up", shortcut: .init(.upArrow, modifiers: [.command, .option])),
        .init(titleKey: "Move Group Down", shortcut: .init(.downArrow, modifiers: [.command, .option]))
    ]

    static func conflict(for shortcut: KeyboardShortcuts.Shortcut) -> ShortcutAssignmentConflict? {
        guard let command = shortcuts.first(where: { $0.shortcut == shortcut }) else {
            return nil
        }

        return ShortcutAssignmentConflict(
            shortcut: shortcut,
            owner: .appCommand(titleKey: command.titleKey)
        )
    }
}

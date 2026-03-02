import Foundation

// MARK: - URL Router Logic

/// Pure functions extracted from ShortcutCycleURLRouter for testability.
/// These functions contain no UI, AppKit, or singleton dependencies.
public enum URLRouterLogic {

    // MARK: - Value Parsers

    /// Parses a string value into a Bool, accepting common truthy/falsy representations.
    public static func parseBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on", "enabled":
            return true
        case "0", "false", "no", "off", "disabled":
            return false
        default:
            return nil
        }
    }

    /// Parses a theme string into its canonical raw value ("system", "light", or "dark").
    /// Returns `nil` for unrecognized values.
    public static func parseTheme(_ value: String) -> String? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "system", "default":
            return "system"
        case "light":
            return "light"
        case "dark":
            return "dark"
        default:
            return nil
        }
    }

    /// Parses a language code, returning its canonical form from the supported list.
    /// Accepts "system" (case-insensitive) as a special value.
    /// - Parameter value: The raw language code string.
    /// - Parameter supportedCodes: Canonical language codes (e.g., ["en", "pt-BR", "zh-Hans"]).
    /// - Returns: The canonical language code, "system", or `nil` if unsupported.
    public static func parseLanguage(_ value: String, supportedCodes: [String]) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("system") == .orderedSame {
            return "system"
        }

        let candidate = trimmed.lowercased()
        return supportedCodes.first(where: { $0.lowercased() == candidate })
    }

    // MARK: - Group Resolution

    /// Resolves a URL group target to an AppGroup from the provided list.
    /// - Parameter target: The target selector (nil means "current" or "first enabled").
    /// - Parameter groups: All available groups.
    /// - Parameter selectedGroup: The currently selected group, if any.
    /// - Returns: The matched group, or `nil` if no match found.
    public static func resolveGroup(
        _ target: URLGroupTarget?,
        groups: [AppGroup],
        selectedGroup: AppGroup?
    ) -> AppGroup? {
        guard let target else {
            if let selectedGroup, selectedGroup.isEnabled {
                return selectedGroup
            }
            return groups.first(where: \.isEnabled)
        }

        switch target {
        case .id(let id):
            return groups.first(where: { $0.id == id })
        case .name(let name):
            return groups.first(where: {
                $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            })
        case .index(let index):
            let resolvedIndex = index - 1
            guard groups.indices.contains(resolvedIndex) else { return nil }
            return groups[resolvedIndex]
        }
    }

    // MARK: - Error Message Formatters

    /// Returns a user-facing error message for export path validation failures.
    /// - Parameter error: The validation error.
    /// - Parameter home: The sandbox home directory path (e.g., from `NSHomeDirectory()`).
    public static func exportPathErrorMessage(
        for error: URLCommandFileValidation.ValidationError,
        home: String
    ) -> String {
        switch error {
        case .emptyPath, .invalidPath:
            return "Invalid export path. Provide a non-empty file path, or omit the path to use the default container location."
        case .pathOutsideContainer:
            return "Invalid export path. Use a location inside this app's container (for example, \(home)/tmp), or omit the path to use the default."
        default:
            return "Invalid export path: \(error.localizedDescription)"
        }
    }

    /// Returns a user-facing error message for import path validation failures.
    /// - Parameter error: The validation error.
    /// - Parameter home: The sandbox home directory path (e.g., from `NSHomeDirectory()`).
    public static func importPathErrorMessage(
        for error: URLCommandFileValidation.ValidationError,
        home: String
    ) -> String {
        switch error {
        case .emptyPath, .invalidPath:
            return "Invalid import path. Provide a non-empty file path or file URL."
        case .pathOutsideContainer:
            return "Invalid import path. Use a location inside this app's container (for example, \(home)/tmp)."
        default:
            return "Invalid import path: \(error.localizedDescription)"
        }
    }

    /// Returns a user-facing error message for backup target validation failures.
    /// - Parameter error: The validation error.
    /// - Parameter home: The sandbox home directory path (e.g., from `NSHomeDirectory()`).
    public static func backupTargetErrorMessage(
        for error: URLCommandFileValidation.ValidationError,
        home: String
    ) -> String {
        switch error {
        case .emptyPath, .invalidPath:
            return "Invalid backup path. Provide an absolute file path or file URL."
        case .pathOutsideContainer:
            return "Invalid backup path. Use a location inside this app's container (for example, \(home)/tmp)."
        case .invalidBackupName:
            return "Invalid backup name. Use a backup filename only (no path separators or '..')."
        case .backupOutsideDirectory:
            return "Invalid backup target. Backup names must resolve inside the automatic backup directory."
        case .backupIndexOutOfRange:
            return "Backup index is out of range."
        case .noBackupsAvailable:
            return "No backup files are available to restore."
        }
    }
}

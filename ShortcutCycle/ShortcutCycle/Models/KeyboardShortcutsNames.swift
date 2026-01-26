import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Generate a shortcut name for a group UUID
    /// This provides a consistent way to reference shortcuts across the app
    static func forGroup(_ id: UUID) -> Self {
        Self("group-\(id.uuidString)")
    }
    
    /// Global shortcut to toggle the settings window
    static let toggleSettings = Self("toggleSettings")
}

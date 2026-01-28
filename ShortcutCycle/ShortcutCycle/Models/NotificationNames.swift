import Foundation

public extension Notification.Name {
    /// Posted when groups or shortcuts have changed and need re-registration
    static let shortcutsNeedUpdate = Notification.Name("ShortcutsNeedUpdate")
}

import Foundation
import AppKit

enum SettingsWindowAppPolicy {
    static func shouldHandleDockReopen(hasVisibleWindows: Bool) -> Bool {
        !hasVisibleWindows
    }
}

@MainActor
enum SettingsWindowLifecycleCoordinator {
    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "settings"
    }

    static func shouldHandleDockReopen(hasVisibleWindows: Bool) -> Bool {
        SettingsWindowAppPolicy.shouldHandleDockReopen(
            hasVisibleWindows: hasVisibleWindows
        )
    }
}

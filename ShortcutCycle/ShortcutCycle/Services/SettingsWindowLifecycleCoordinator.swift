import Foundation
import AppKit

@MainActor
enum SettingsWindowLifecycleCoordinator {
    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "settings"
    }

    static func visibleSettingsWindow(in windows: [NSWindow]) -> NSWindow? {
        windows.first { window in
            isSettingsWindow(window) && window.isVisible
        }
    }

    static func visibleOffSpaceSettingsWindow(in windows: [NSWindow]) -> NSWindow? {
        windows.first { window in
            isSettingsWindow(window) && window.isVisible && !window.isOnActiveSpace
        }
    }

    static func shouldHandleDockReopen(hasVisibleWindows: Bool) -> Bool {
        !hasVisibleWindows
    }
}

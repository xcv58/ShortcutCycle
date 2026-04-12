import Foundation
import AppKit

enum SettingsWindowLifecycleCoordinator {
    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "settings"
    }

    static func isActiveSettingsWindow(_ window: NSWindow) -> Bool {
        isSettingsWindow(window) && window.isVisible && (window.isKeyWindow || window.isMainWindow)
    }

    static func anyVisibleSettingsWindow(in windows: [NSWindow]) -> NSWindow? {
        windows.first { window in
            isSettingsWindow(window) && window.isVisible
        }
    }

    static func visibleOffSpaceSettingsWindow(in windows: [NSWindow]) -> NSWindow? {
        windows.first { window in
            isSettingsWindow(window) && window.isVisible && !window.isOnActiveSpace
        }
    }

    static func activationPolicy(for window: NSWindow?) -> NSApplication.ActivationPolicy {
        guard let window, isActiveSettingsWindow(window) else {
            return .accessory
        }

        return .regular
    }
}

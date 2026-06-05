import Foundation
import AppKit

enum SettingsWindowToggleAction: Equatable {
    case open
    case focus
    case dismiss
}

enum SettingsWindowLifecycleCoordinator {
    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "settings"
    }

    static func isActiveSettingsWindow(_ window: NSWindow) -> Bool {
        isSettingsWindow(window)
            && window.isVisible
            && (window.isKeyWindow || window.isMainWindow || hasVisibleAttachedSheet(window))
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

    static func toggleAction(for window: NSWindow?) -> SettingsWindowToggleAction {
        guard let window, isSettingsWindow(window), window.isVisible else {
            return .open
        }

        if isDismissibleSettingsWindow(window) {
            return .dismiss
        }

        return .focus
    }

    static func isDismissibleSettingsWindow(_ window: NSWindow) -> Bool {
        isSettingsWindow(window)
            && window.isVisible
            && window.isKeyWindow
            && !hasVisibleAttachedSheet(window)
    }

    private static func hasVisibleAttachedSheet(_ window: NSWindow) -> Bool {
        guard let sheet = window.attachedSheet else { return false }
        return sheet.isVisible
    }
}

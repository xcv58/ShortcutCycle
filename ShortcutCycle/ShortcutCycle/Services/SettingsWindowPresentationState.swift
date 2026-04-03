import Foundation
import AppKit

struct SettingsWindowSnapshot: Equatable {
    let isSettingsWindow: Bool
    let isVisible: Bool
    let isOnActiveSpace: Bool
}

enum SettingsWindowHUDPresentationPolicy {
    static func shouldUseDeferredActivation(windows: [SettingsWindowSnapshot]) -> Bool {
        windows.contains { snapshot in
            snapshot.isSettingsWindow && snapshot.isVisible && !snapshot.isOnActiveSpace
        }
    }

    static func shouldHandleDockReopen(hasVisibleWindows: Bool) -> Bool {
        !hasVisibleWindows
    }
}

@MainActor
enum SettingsWindowLifecycleCoordinator {
    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "settings"
    }

    static func hasOffSpaceSettingsWindow(in windows: [NSWindow]) -> Bool {
        SettingsWindowHUDPresentationPolicy.shouldUseDeferredActivation(
            windows: windows.map { window in
                SettingsWindowSnapshot(
                    isSettingsWindow: isSettingsWindow(window),
                    isVisible: window.isVisible,
                    isOnActiveSpace: window.isOnActiveSpace
                )
            }
        )
    }

    static func shouldHandleDockReopen(hasVisibleWindows: Bool) -> Bool {
        SettingsWindowHUDPresentationPolicy.shouldHandleDockReopen(
            hasVisibleWindows: hasVisibleWindows
        )
    }
}

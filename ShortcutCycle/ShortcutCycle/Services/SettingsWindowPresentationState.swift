import Foundation
import AppKit

enum SettingsWindowPresentationAction: Equatable {
    case bringToFront
    case restoreHiddenWindow
}

@MainActor
struct SettingsWindowPresentationState {
    private(set) var isTemporarilyHidden = false

    mutating func markTemporarilyHidden() {
        isTemporarilyHidden = true
    }

    mutating func presentationActionForExistingWindow(isVisible: Bool) -> SettingsWindowPresentationAction {
        defer { isTemporarilyHidden = false }

        if isTemporarilyHidden || !isVisible {
            return .restoreHiddenWindow
        }

        return .bringToFront
    }

    mutating func windowDidClose() {
        isTemporarilyHidden = false
    }

    func shouldHandleDockReopen(hasVisibleWindows: Bool) -> Bool {
        isTemporarilyHidden || !hasVisibleWindows
    }
}

@MainActor
enum SettingsWindowLifecycleCoordinator {
    private static var presentationState = SettingsWindowPresentationState()

    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "settings"
    }

    static func markTemporarilyHidden() {
        presentationState.markTemporarilyHidden()
    }

    static func presentationAction(for window: NSWindow) -> SettingsWindowPresentationAction {
        presentationState.presentationActionForExistingWindow(isVisible: window.isVisible)
    }

    static func windowDidClose() {
        presentationState.windowDidClose()
    }

    static func shouldHandleDockReopen(hasVisibleWindows: Bool) -> Bool {
        presentationState.shouldHandleDockReopen(hasVisibleWindows: hasVisibleWindows)
    }
}

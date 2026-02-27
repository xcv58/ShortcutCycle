import Foundation
import AppKit
import ApplicationServices

// MARK: - Window Info

/// Information about a single window from the Accessibility API
struct WindowInfo {
    let title: String?
    let index: Int
    let isMinimized: Bool
    let axElement: AXUIElement
}

// MARK: - Window Enumerator

/// Enumerates and raises individual windows via the macOS Accessibility API
@MainActor
class WindowEnumerator {
    static let shared = WindowEnumerator()

    private init() {}

    // MARK: - Accessibility Permission

    /// Whether the current process has Accessibility permission
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Window Enumeration

    /// Returns all standard windows for the given process
    func windows(for pid: pid_t) -> [WindowInfo] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let windowArray = windowsRef as? [AXUIElement] else {
            return []
        }

        var infos: [WindowInfo] = []
        for (index, window) in windowArray.enumerated() {
            // Filter to standard windows only (skip utility panels, sheets, etc.)
            guard windowRole(for: window) == kAXWindowRole else { continue }

            let title = windowTitle(for: window)
            let minimized = isWindowMinimized(window)

            infos.append(WindowInfo(
                title: title,
                index: index,
                isMinimized: minimized,
                axElement: window
            ))
        }
        return infos
    }

    // MARK: - Window Activation

    /// Raises a specific window and activates its owning process.
    /// - Returns: true if the window was successfully raised
    @discardableResult
    func raiseWindow(_ info: WindowInfo, pid: pid_t) -> Bool {
        // Unminimize if needed
        if info.isMinimized {
            AXUIElementSetAttributeValue(
                info.axElement,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
        }

        // Raise the specific window
        let raiseResult = AXUIElementPerformAction(info.axElement, kAXRaiseAction as CFString)

        // Activate the app WITHOUT activateAllWindows so only this window comes forward
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "")
        if let app = NSRunningApplication(processIdentifier: pid) ?? apps.first {
            app.activate()
        } else {
            // Fallback: find by PID in running apps
            let running = NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
            running?.activate()
        }

        return raiseResult == .success
    }

    // MARK: - AX Helpers

    private func windowTitle(for element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        guard result == .success, let title = titleRef as? String, !title.isEmpty else {
            return nil
        }
        return title
    }

    private func windowRole(for element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard result == .success, let role = roleRef as? String else {
            return nil
        }
        return role
    }

    private func isWindowMinimized(_ element: AXUIElement) -> Bool {
        var minimizedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
        guard result == .success, let minimized = minimizedRef as? Bool else {
            return false
        }
        return minimized
    }
}

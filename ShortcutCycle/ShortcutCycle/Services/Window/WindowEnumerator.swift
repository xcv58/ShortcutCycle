import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Window Info

/// Information about a single window
struct WindowInfo {
    let title: String?
    let index: Int
    let isMinimized: Bool
    /// CGWindowID for CGWindowList-based enumeration
    let windowNumber: CGWindowID
    /// Lazily-created AXUIElement for activation
    let axElement: AXUIElement
}

// MARK: - Window Enumerator

/// Enumerates windows via CGWindowList (sandbox-safe) and raises them via AX API
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

    // MARK: - Window Enumeration (CGWindowList — works in sandbox)

    /// Returns all standard windows for the given process
    func windows(for pid: pid_t) -> [WindowInfo] {
        // Phase 1: Use CGWindowList to enumerate windows (sandbox-safe)
        let cgWindows = cgWindowInfos(for: pid)

        if cgWindows.isEmpty {
            return []
        }

        // Phase 2: Get AX windows to pair them with CG windows for activation
        let axWindows = axWindowElements(for: pid)

        var infos: [WindowInfo] = []
        for (index, cgWindow) in cgWindows.enumerated() {
            // Try to find a matching AX element by title
            let axElement = matchAXElement(for: cgWindow, in: axWindows, pid: pid)

            infos.append(WindowInfo(
                title: cgWindow.title,
                index: index,
                isMinimized: cgWindow.isMinimized,
                windowNumber: cgWindow.windowNumber,
                axElement: axElement
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
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        } else {
            let running = NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
            running?.activate()
        }

        return raiseResult == .success
    }

    // MARK: - CGWindowList Helpers

    private struct CGWindowInfo {
        let windowNumber: CGWindowID
        let title: String?
        let isOnScreen: Bool
        let isMinimized: Bool
        let layer: Int
    }

    /// Get window info from CGWindowList (works from sandboxed apps)
    private func cgWindowInfos(for pid: pid_t) -> [CGWindowInfo] {
        // Use .optionAll to include minimized (off-screen) windows
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var windows: [CGWindowInfo] = []
        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let windowNumber = entry[kCGWindowNumber as String] as? CGWindowID,
                  let layer = entry[kCGWindowLayer as String] as? Int else {
                continue
            }

            // Layer 0 = normal windows (skip menu bar items, overlays, etc.)
            guard layer == 0 else { continue }

            let title = entry[kCGWindowName as String] as? String
            let isOnScreen = entry[kCGWindowIsOnscreen as String] as? Bool ?? false

            // Skip windows with no name and not on screen (likely internal)
            // But include minimized windows (not on screen but have a title)
            let isMinimized = !isOnScreen

            // Filter: include windows that are on-screen OR have a title (minimized with a name)
            guard isOnScreen || (title != nil && !title!.isEmpty) else { continue }

            windows.append(CGWindowInfo(
                windowNumber: windowNumber,
                title: title,
                isOnScreen: isOnScreen,
                isMinimized: isMinimized,
                layer: layer
            ))
        }

        return windows
    }

    // MARK: - AX Helpers

    /// Get AX window elements for pairing with CG windows
    private func axWindowElements(for pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let windowArray = windowsRef as? [AXUIElement] else {
            return []
        }
        return windowArray
    }

    /// Match a CG window to its AX element by title (best-effort)
    private func matchAXElement(for cgWindow: CGWindowInfo, in axWindows: [AXUIElement], pid: pid_t) -> AXUIElement {
        // Try matching by title
        if let cgTitle = cgWindow.title, !cgTitle.isEmpty {
            for ax in axWindows {
                if axWindowTitle(for: ax) == cgTitle {
                    return ax
                }
            }
        }

        // Fallback: if only one AX window or we can't match, use index-based or first
        // Create an app-level AX element as a fallback (can still activate the app)
        return AXUIElementCreateApplication(pid)
    }

    private func axWindowTitle(for element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        guard result == .success, let title = titleRef as? String, !title.isEmpty else {
            return nil
        }
        return title
    }
}

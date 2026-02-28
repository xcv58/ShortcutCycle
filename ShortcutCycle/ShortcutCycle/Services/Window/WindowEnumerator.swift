import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import os.log

// MARK: - Window Info

/// Information about a single window
struct WindowInfo {
    let title: String?
    let index: Int
    /// CGWindowID for CGWindowList-based enumeration
    let windowNumber: CGWindowID?
    /// AXUIElement for activation — window-level when possible, app-level as fallback
    let axElement: AXUIElement
}

// MARK: - Window Enumerator

/// Enumerates windows via AX API (primary) with CGWindowList fallback,
/// and raises windows via AX with synthetic-click fallback.
@MainActor
class WindowEnumerator {
    static let shared = WindowEnumerator()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.xcv58.ShortcutCycle",
        category: "WindowEnumerator"
    )

    /// Cache of AXUIElements keyed by "{pid}::w{index}" for fallback activation.
    private var windowCache: [String: AXUIElement] = [:]
    /// Cache of CGWindowID keyed by "{pid}::w{index}" for robust frontmost verification.
    private var windowNumberCache: [String: CGWindowID] = [:]
    /// Cache of AXUIElements keyed by "{pid}::wid{windowNumber}" for stable, index-independent activation.
    private var windowNumberElementCache: [String: AXUIElement] = [:]

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

    // MARK: - Window Enumeration (AX-first, CGWindowList fallback)

    /// Returns all standard windows for the given process
    func windows(for pid: pid_t) -> [WindowInfo] {
        clearCache(for: pid)

        // Try AX first — gives titles + window-level elements for activation
        let axWindows = axWindowElements(for: pid)
        if !axWindows.isEmpty {
            let infos = axWindowInfos(from: axWindows, pid: pid)
            Self.logger.debug("AX-first: found \(infos.count) windows for pid \(pid)")
            return infos
        }

        // Fallback: CGWindowList with index-based AX matching
        Self.logger.debug("AX returned empty for pid \(pid), falling back to CGWindowList")
        return cgFallbackWindowInfos(for: pid)
    }

    // MARK: - Window Activation

    /// Raises a cached window by pid and target identifiers.
    /// Uses the AXUIElement cached during enumeration to avoid re-enumeration race conditions.
    /// Tries AX raise first, then falls back to synthetic title-bar click if needed.
    /// - Returns: true if a raise attempt was performed
    @discardableResult
    func raiseWindow(pid: pid_t, windowIndex: Int?, windowNumber: CGWindowID? = nil) -> Bool {
        guard let target = resolveWindowTarget(pid: pid, windowIndex: windowIndex, windowNumber: windowNumber) else {
            let fallbackKey = windowIndex.map { "\(pid)::w\($0)" } ?? "\(pid)::wid\(windowNumber.map(String.init) ?? "nil")"
            Self.logger.warning("No cached AXUIElement for \(fallbackKey), cannot raise window")
            return false
        }

        let axElement = target.axElement
        let targetWindowNumber = target.windowNumber
        let cacheKey = target.debugKey
        Self.logger.info("raiseWindow start key=\(cacheKey, privacy: .public) targetWin=\(String(describing: targetWindowNumber), privacy: .public)")

        activateApp(pid: pid)

        let didAXRaise = performAXRaise(axElement, pid: pid, cacheKey: cacheKey)
        if isTargetWindowFocused(axElement, pid: pid, targetWindowNumber: targetWindowNumber) {
            Self.logger.info("raiseWindow AX verified success key=\(cacheKey, privacy: .public)")
            return true
        }

        // Chromium apps often ignore AX raise/main-window requests.
        // Fallback: synthetic click on the window title-bar region.
        let didClickRaise = raiseBySyntheticTitleBarClick(
            axElement,
            pid: pid,
            targetWindowNumber: targetWindowNumber,
            cacheKey: cacheKey
        )
        if isTargetWindowFocused(axElement, pid: pid, targetWindowNumber: targetWindowNumber) {
            Self.logger.info("raiseWindow click fallback success key=\(cacheKey, privacy: .public)")
            return true
        }

        Self.logger.warning("raiseWindow unresolved key=\(cacheKey, privacy: .public) didAX=\(didAXRaise) didClick=\(didClickRaise)")
        return didAXRaise || didClickRaise
    }

    @discardableResult
    func raiseWindow(pid: pid_t, windowIndex: Int) -> Bool {
        raiseWindow(pid: pid, windowIndex: windowIndex, windowNumber: nil)
    }

    private struct WindowTarget {
        let axElement: AXUIElement
        let windowNumber: CGWindowID?
        let debugKey: String
    }

    private func resolveWindowTarget(pid: pid_t, windowIndex: Int?, windowNumber: CGWindowID?) -> WindowTarget? {
        if let windowNumber {
            let numberKey = windowNumberKey(pid: pid, windowNumber: windowNumber)

            if let byNumber = windowNumberElementCache[numberKey] {
                return WindowTarget(axElement: byNumber, windowNumber: windowNumber, debugKey: numberKey)
            }

            if let scanned = findAXWindowElement(for: pid, windowNumber: windowNumber) {
                windowNumberElementCache[numberKey] = scanned
                return WindowTarget(axElement: scanned, windowNumber: windowNumber, debugKey: numberKey)
            }
        }

        if let windowIndex {
            let indexKey = indexKey(pid: pid, windowIndex: windowIndex)
            guard let byIndex = windowCache[indexKey] else {
                return nil
            }

            let resolvedNumber = windowNumber ?? windowNumberCache[indexKey]
            if let resolvedNumber {
                let numberKey = windowNumberKey(pid: pid, windowNumber: resolvedNumber)
                windowNumberElementCache[numberKey] = byIndex
            }
            return WindowTarget(axElement: byIndex, windowNumber: resolvedNumber, debugKey: indexKey)
        }

        return nil
    }

    private func findAXWindowElement(for pid: pid_t, windowNumber: CGWindowID) -> AXUIElement? {
        for element in axWindowElements(for: pid) {
            if axWindowNumber(for: element) == windowNumber {
                return element
            }
        }
        return nil
    }

    private func activateApp(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.unhide()
            app.activate(options: [])
            return
        }

        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) {
            running.unhide()
            running.activate(options: [])
        }
    }

    /// Performs AX raise + main-window requests
    private func performAXRaise(_ axElement: AXUIElement, pid: pid_t, cacheKey: String) -> Bool {
        let raiseResult = AXUIElementPerformAction(axElement, kAXRaiseAction as CFString)
        if raiseResult != .success {
            Self.logger.warning("AXRaise failed (\(raiseResult.rawValue)) for \(cacheKey)")
        }

        _ = AXUIElementSetAttributeValue(
            axElement,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )

        let appElement = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetAttributeValue(
            appElement,
            kAXMainWindowAttribute as CFString,
            axElement
        )
        _ = AXUIElementSetAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            axElement
        )
        _ = AXUIElementSetAttributeValue(
            axElement,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        return raiseResult == .success
    }

    private func isTargetWindowFocused(_ axElement: AXUIElement, pid: pid_t, targetWindowNumber: CGWindowID?) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return false
        }

        // Strong check first: compare CGWindowID of target vs actual top window.
        if let targetWindowNumber,
           let topWindowNumber = topWindowNumber(for: pid) {
            Self.logger.debug("focus check pid=\(pid) targetWin=\(targetWindowNumber) topWin=\(topWindowNumber)")
            return targetWindowNumber == topWindowNumber
        }

        // Fallback check when CGWindowID is unavailable.
        let appElement = AXUIElementCreateApplication(pid)
        if appAttributeWindowMatches(appElement, attribute: kAXFocusedWindowAttribute as String, target: axElement) {
            return true
        }
        if appAttributeWindowMatches(appElement, attribute: kAXMainWindowAttribute as String, target: axElement) {
            return true
        }
        return false
    }

    private func appAttributeWindowMatches(_ appElement: AXUIElement, attribute: String, target: AXUIElement) -> Bool {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, attribute as CFString, &valueRef)
        guard result == .success, let valueRef else {
            return false
        }
        return CFEqual(valueRef, target)
    }

    private func raiseBySyntheticTitleBarClick(
        _ axElement: AXUIElement,
        pid: pid_t,
        targetWindowNumber: CGWindowID?,
        cacheKey: String
    ) -> Bool {
        let frame: CGRect? = {
            if let targetWindowNumber,
               let cgFrame = cgWindowFrame(windowNumber: targetWindowNumber) {
                return cgFrame
            }
            return axWindowFrame(for: axElement)
        }()

        guard let frame else {
            Self.logger.warning("Cannot read target frame for \(cacheKey); click fallback skipped")
            return false
        }

        for clickPoint in titleBarClickPoints(for: frame) {
            if postSyntheticClick(at: clickPoint) {
                if isTargetWindowFocused(axElement, pid: pid, targetWindowNumber: targetWindowNumber) {
                    return true
                }
            }
        }
        return false
    }

    private func titleBarClickPoints(for frame: CGRect) -> [CGPoint] {
        let safeInset = max(8, min(22, frame.height * 0.12))
        let centerX = frame.midX

        let first = CGPoint(x: centerX, y: frame.minY + safeInset)
        let second = CGPoint(x: centerX, y: frame.maxY - safeInset)

        if abs(first.y - second.y) < 1 {
            return [first]
        }
        return [first, second]
    }

    private func postSyntheticClick(at point: CGPoint) -> Bool {
        let originalLocation = CGEvent(source: nil)?.location

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let move = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left
              ),
              let down = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
              ),
              let up = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
              ) else {
            return false
        }

        move.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        if let originalLocation,
           originalLocation != point,
           let restoreMove = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: originalLocation,
            mouseButton: .left
           ) {
            restoreMove.post(tap: .cghidEventTap)
        }

        return true
    }

    private func axWindowFrame(for element: AXUIElement) -> CGRect? {
        guard let origin = axPointAttribute(for: element, attribute: kAXPositionAttribute as String),
              let size = axSizeAttribute(for: element, attribute: kAXSizeAttribute as String) else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    private func axPointAttribute(for element: AXUIElement, attribute: String) -> CGPoint? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard result == .success, let valueRef else {
            return nil
        }
        guard CFGetTypeID(valueRef) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(valueRef, to: AXValue.self)

        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func axSizeAttribute(for element: AXUIElement, attribute: String) -> CGSize? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard result == .success, let valueRef else {
            return nil
        }
        guard CFGetTypeID(valueRef) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(valueRef, to: AXValue.self)

        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func topWindowNumber(for pid: pid_t) -> CGWindowID? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let windowNumber = entry[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            return windowNumber
        }

        return nil
    }

    private func cgWindowFrame(windowNumber: CGWindowID) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowNumber) as? [[String: Any]],
              let entry = windowList.first,
              let boundsObject = entry[kCGWindowBounds as String] else {
            return nil
        }

        guard let boundsDict = boundsObject as? NSDictionary else {
            return nil
        }
        var bounds = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDict, &bounds) else {
            return nil
        }

        return bounds
    }

    private func indexKey(pid: pid_t, windowIndex: Int) -> String {
        "\(pid)::w\(windowIndex)"
    }

    private func windowNumberKey(pid: pid_t, windowNumber: CGWindowID) -> String {
        "\(pid)::wid\(windowNumber)"
    }

    private func clearCache(for pid: pid_t) {
        let pidPrefix = "\(pid)::"
        windowCache = windowCache.filter { !$0.key.hasPrefix(pidPrefix) }
        windowNumberCache = windowNumberCache.filter { !$0.key.hasPrefix(pidPrefix) }
        windowNumberElementCache = windowNumberElementCache.filter { !$0.key.hasPrefix(pidPrefix) }
    }

    private func axWindowNumber(for element: AXUIElement) -> CGWindowID? {
        let axWindowNumberAttribute = "AXWindowNumber" as CFString
        var numberRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, axWindowNumberAttribute, &numberRef)
        guard result == .success,
              let number = numberRef as? NSNumber else {
            return nil
        }
        return CGWindowID(number.uint32Value)
    }

    // MARK: - AX-First Enumeration

    /// Build WindowInfo array directly from AX window elements
    private func axWindowInfos(from axWindows: [AXUIElement], pid: pid_t) -> [WindowInfo] {
        var infos: [WindowInfo] = []
        var index = 0

        for ax in axWindows {
            // Filter to standard windows only (skip panels, sheets, popovers)
            guard axWindowRole(for: ax) == kAXWindowRole as String else { continue }

            // Skip minimized windows
            if axWindowIsMinimized(for: ax) { continue }

            let title = axWindowTitle(for: ax)
            let resolvedWindowNumber = axWindowNumber(for: ax)

            // Cache the AXUIElement for stable activation later
            let cacheKey = indexKey(pid: pid, windowIndex: index)
            windowCache[cacheKey] = ax
            if let resolvedWindowNumber {
                windowNumberCache[cacheKey] = resolvedWindowNumber
                windowNumberElementCache[windowNumberKey(pid: pid, windowNumber: resolvedWindowNumber)] = ax
            } else {
                windowNumberCache.removeValue(forKey: cacheKey)
            }

            infos.append(WindowInfo(
                title: title,
                index: index,
                windowNumber: resolvedWindowNumber,
                axElement: ax
            ))
            index += 1
        }

        return infos
    }

    // MARK: - CGWindowList Fallback

    private struct CGWindowInfo {
        let windowNumber: CGWindowID
        let title: String?
        let isOnScreen: Bool
        let layer: Int
    }

    /// Fallback: enumerate via CGWindowList, match to AX elements by index
    private func cgFallbackWindowInfos(for pid: pid_t) -> [WindowInfo] {
        let cgWindows = cgWindowInfos(for: pid)
        if cgWindows.isEmpty { return [] }

        // Get AX windows for index-based matching
        let axWindows = axWindowElements(for: pid)
        let appElement = AXUIElementCreateApplication(pid)

        var infos: [WindowInfo] = []
        for (index, cgWindow) in cgWindows.enumerated() {
            // Nth CG window → Nth AX window element; fall back to app-level
            let axElement = index < axWindows.count ? axWindows[index] : appElement

            // Cache the AXUIElement for stable activation later
            let cacheKey = indexKey(pid: pid, windowIndex: index)
            windowCache[cacheKey] = axElement
            windowNumberCache[cacheKey] = cgWindow.windowNumber
            windowNumberElementCache[windowNumberKey(pid: pid, windowNumber: cgWindow.windowNumber)] = axElement

            infos.append(WindowInfo(
                title: cgWindow.title,
                index: index,
                windowNumber: cgWindow.windowNumber,
                axElement: axElement
            ))
        }
        return infos
    }

    /// Get window info from CGWindowList (works from sandboxed apps)
    private func cgWindowInfos(for pid: pid_t) -> [CGWindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
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

            guard isOnScreen else { continue }

            windows.append(CGWindowInfo(
                windowNumber: windowNumber,
                title: title,
                isOnScreen: isOnScreen,
                layer: layer
            ))
        }

        return windows
    }

    // MARK: - AX Helpers

    /// Get AX window elements for the given process
    private func axWindowElements(for pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let windowArray = windowsRef as? [AXUIElement] else {
            return []
        }
        return windowArray
    }

    /// Read kAXTitleAttribute from an AX element
    private func axWindowTitle(for element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        guard result == .success, let title = titleRef as? String, !title.isEmpty else {
            return nil
        }
        return title
    }

    /// Read kAXMinimizedAttribute from an AX element
    private func axWindowIsMinimized(for element: AXUIElement) -> Bool {
        var minimizedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
        guard result == .success, let minimized = minimizedRef as? Bool else {
            return false
        }
        return minimized
    }

    /// Read kAXRoleAttribute from an AX element
    private func axWindowRole(for element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        guard result == .success, let role = roleRef as? String else {
            return nil
        }
        return role
    }
}

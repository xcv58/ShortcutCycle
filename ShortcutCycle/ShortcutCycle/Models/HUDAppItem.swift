import Foundation
import AppKit

/// Common app item used in HUD
public struct HUDAppItem: Identifiable, Equatable, @unchecked Sendable {
    /// Unique identifier: "{bundleId}::{pid}" for running apps, "{bundleId}::{pid}::w{index}" for per-window, or "{bundleId}" for non-running
    public let id: String
    /// The app's bundle identifier
    public let bundleId: String
    /// Process ID for running instances (nil for non-running apps)
    public let pid: pid_t?
    public let name: String
    public let icon: NSImage?
    public let isRunning: Bool

    // MARK: - Per-Window Mode Properties

    /// Window title from AX API (nil for process-level items)
    public let windowTitle: String?
    /// Index in the AX window list (nil for process-level items)
    public let windowIndex: Int?
    /// Stable CGWindowID when available (preferred for activation)
    public let windowNumber: CGWindowID?
    /// Original app name (shown as subtitle when windowTitle is primary)
    public let appName: String?

    /// Initialize with a running app instance
    public init(runningApp: NSRunningApplication, name: String? = nil, icon: NSImage? = nil) {
        let bundleId = runningApp.bundleIdentifier ?? ""
        self.bundleId = bundleId
        self.pid = runningApp.processIdentifier
        self.id = "\(bundleId)::\(runningApp.processIdentifier)"
        self.name = name ?? runningApp.localizedName ?? "App"
        self.icon = icon ?? runningApp.icon
        self.isRunning = true
        self.windowTitle = nil
        self.windowIndex = nil
        self.windowNumber = nil
        self.appName = nil
    }

    /// Initialize for a specific window of a running app (per-window mode)
    public init(runningApp: NSRunningApplication, windowTitle: String?, windowIndex: Int, windowNumber: CGWindowID? = nil, name: String? = nil, icon: NSImage? = nil) {
        self.init(
            bundleId: runningApp.bundleIdentifier ?? "",
            pid: runningApp.processIdentifier,
            windowTitle: windowTitle,
            windowIndex: windowIndex,
            windowNumber: windowNumber,
            name: name ?? runningApp.localizedName ?? "App",
            icon: icon ?? runningApp.icon
        )
    }

    /// Initialize for a specific window with explicit parameters (testable, no NSRunningApplication needed)
    public init(bundleId: String, pid: pid_t, windowTitle: String?, windowIndex: Int, windowNumber: CGWindowID? = nil, name: String, icon: NSImage? = nil) {
        self.bundleId = bundleId
        self.pid = pid
        self.id = "\(bundleId)::\(pid)::w\(windowIndex)"
        self.appName = name
        self.name = windowTitle ?? "\(name) - Window \(windowIndex + 1)"
        self.icon = icon
        self.isRunning = true
        self.windowTitle = windowTitle
        self.windowIndex = windowIndex
        self.windowNumber = windowNumber
    }

    /// Initialize for a non-running app
    public init(bundleId: String, name: String, icon: NSImage?) {
        self.bundleId = bundleId
        self.pid = nil
        self.id = bundleId
        self.name = name
        self.icon = icon
        self.isRunning = false
        self.windowTitle = nil
        self.windowIndex = nil
        self.windowNumber = nil
        self.appName = nil
    }

    /// Legacy initializer for compatibility (creates non-running style ID)
    public init(id: String, name: String, icon: NSImage?, isRunning: Bool) {
        self.id = id
        self.bundleId = id
        self.pid = nil
        self.name = name
        self.icon = icon
        self.isRunning = isRunning
        self.windowTitle = nil
        self.windowIndex = nil
        self.windowNumber = nil
        self.appName = nil
    }

    // For Equatable
    public static func == (lhs: HUDAppItem, rhs: HUDAppItem) -> Bool {
        lhs.id == rhs.id
    }
}

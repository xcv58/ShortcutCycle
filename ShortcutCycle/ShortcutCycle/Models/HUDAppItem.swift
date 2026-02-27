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
    /// Whether the window is minimized
    public let isMinimized: Bool
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
        self.isMinimized = false
        self.appName = nil
    }

    /// Initialize for a specific window of a running app (per-window mode)
    public init(runningApp: NSRunningApplication, windowTitle: String?, windowIndex: Int, isMinimized: Bool = false, name: String? = nil, icon: NSImage? = nil) {
        let bundleId = runningApp.bundleIdentifier ?? ""
        self.bundleId = bundleId
        self.pid = runningApp.processIdentifier
        self.id = "\(bundleId)::\(runningApp.processIdentifier)::w\(windowIndex)"
        let resolvedName = name ?? runningApp.localizedName ?? "App"
        self.appName = resolvedName
        self.name = windowTitle ?? "\(resolvedName) - Window \(windowIndex + 1)"
        self.icon = icon ?? runningApp.icon
        self.isRunning = true
        self.windowTitle = windowTitle
        self.windowIndex = windowIndex
        self.isMinimized = isMinimized
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
        self.isMinimized = false
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
        self.isMinimized = false
        self.appName = nil
    }

    // For Equatable
    public static func == (lhs: HUDAppItem, rhs: HUDAppItem) -> Bool {
        lhs.id == rhs.id
    }
}

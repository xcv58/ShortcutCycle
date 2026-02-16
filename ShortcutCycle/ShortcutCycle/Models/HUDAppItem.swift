import Foundation
import AppKit

/// Common app item used in HUD
public struct HUDAppItem: Identifiable, Equatable, @unchecked Sendable {
    /// Unique identifier: "{bundleId}-{pid}" for running apps, or "{bundleId}" for non-running
    public let id: String
    /// The app's bundle identifier
    public let bundleId: String
    /// Process ID for running instances (nil for non-running apps)
    public let pid: pid_t?
    public let name: String
    public let icon: NSImage?
    public let isRunning: Bool

    /// Initialize with a running app instance
    public init(runningApp: NSRunningApplication, name: String? = nil, icon: NSImage? = nil) {
        let bundleId = runningApp.bundleIdentifier ?? ""
        self.bundleId = bundleId
        self.pid = runningApp.processIdentifier
        self.id = "\(bundleId)-\(runningApp.processIdentifier)"
        self.name = name ?? runningApp.localizedName ?? "App"
        self.icon = icon ?? runningApp.icon
        self.isRunning = true
    }

    /// Initialize for a non-running app
    public init(bundleId: String, name: String, icon: NSImage?) {
        self.bundleId = bundleId
        self.pid = nil
        self.id = bundleId
        self.name = name
        self.icon = icon
        self.isRunning = false
    }

    /// Legacy initializer for compatibility (creates non-running style ID)
    public init(id: String, name: String, icon: NSImage?, isRunning: Bool) {
        self.id = id
        self.bundleId = id
        self.pid = nil
        self.name = name
        self.icon = icon
        self.isRunning = isRunning
    }

    // For Equatable
    public static func == (lhs: HUDAppItem, rhs: HUDAppItem) -> Bool {
        lhs.id == rhs.id
    }
}

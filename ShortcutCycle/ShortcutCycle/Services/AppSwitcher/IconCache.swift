import AppKit
import Foundation

class IconCache {
    static let shared = IconCache()
    
    private var cache: [String: NSImage] = [:]
    
    private init() {}
    
    func getIcon(for appItem: AppItem) -> NSImage? {
        if let cached = cache[appItem.bundleIdentifier] {
            return cached
        }
        
        var icon: NSImage?
        
        // Try to get icon from running app first (most accurate)
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: appItem.bundleIdentifier).first {
            icon = runningApp.icon
        }
        
        // Try path
        if icon == nil, let path = appItem.iconPath {
             icon = NSWorkspace.shared.icon(forFile: path)
        }
        
        // Try finding app by bundle ID
        if icon == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appItem.bundleIdentifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
        
        if let icon = icon {
            cache[appItem.bundleIdentifier] = icon
        }
        
        return icon
    }
}

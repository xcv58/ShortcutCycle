import Foundation
import AppKit

/// Handles checking and requesting accessibility permissions
class AccessibilityHelper {
    static let shared = AccessibilityHelper()
    
    private init() {}
    
    /// Check if the app has accessibility permissions
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
    
    /// Request accessibility permission from the user
    /// Opens System Preferences if not already granted
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    /// Open System Preferences to the accessibility pane
    func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

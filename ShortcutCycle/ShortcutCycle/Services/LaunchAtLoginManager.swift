import Foundation
import ServiceManagement
import Combine
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

/// Manages the Launch at Login setting using SMAppService
@MainActor
class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    private static var screenshotOverrideEnabled: Bool?
    
    @Published var isEnabled: Bool {
        didSet {
            if isEnabled != oldValue {
                if Self.screenshotOverrideEnabled == nil {
                    updateLoginItem()
                }
            }
        }
    }
    
    private init() {
        // Read current status from SMAppService
        self.isEnabled = Self.screenshotOverrideEnabled ?? (SMAppService.mainApp.status == .enabled)
    }

    static func setScreenshotOverride(isEnabled: Bool?) {
        screenshotOverrideEnabled = isEnabled
        if let isEnabled {
            shared.isEnabled = isEnabled
        } else {
            shared.refreshStatus()
        }
    }
    
    private func updateLoginItem() {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
            // Revert on failure
            Task { @MainActor in
                self.isEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
    
    /// Refresh the current status from SMAppService
    func refreshStatus() {
        if let override = Self.screenshotOverrideEnabled {
            self.isEnabled = override
            return
        }

        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
}

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
    #if DEBUG
    private static var screenshotOverrideEnabled: Bool?
    #endif
    
    @Published var isEnabled: Bool {
        didSet {
            if isEnabled != oldValue {
                #if DEBUG
                if Self.screenshotOverrideEnabled == nil {
                    updateLoginItem()
                }
                #else
                updateLoginItem()
                #endif
            }
        }
    }
    
    private init() {
        // Read current status from SMAppService
        #if DEBUG
        self.isEnabled = Self.screenshotOverrideEnabled ?? (SMAppService.mainApp.status == .enabled)
        #else
        self.isEnabled = SMAppService.mainApp.status == .enabled
        #endif
    }

    #if DEBUG
    static func setScreenshotOverride(isEnabled: Bool?) {
        screenshotOverrideEnabled = isEnabled
        if let isEnabled {
            shared.isEnabled = isEnabled
        } else {
            shared.refreshStatus()
        }
    }
    #endif
    
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
        #if DEBUG
        if let override = Self.screenshotOverrideEnabled {
            self.isEnabled = override
            return
        }
        #endif

        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
}

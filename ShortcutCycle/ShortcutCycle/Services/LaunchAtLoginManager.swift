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
    
    @Published var isEnabled: Bool {
        didSet {
            if isEnabled != oldValue {
                updateLoginItem()
            }
        }
    }
    
    private init() {
        // Read current status from SMAppService
        self.isEnabled = SMAppService.mainApp.status == .enabled
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
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
}

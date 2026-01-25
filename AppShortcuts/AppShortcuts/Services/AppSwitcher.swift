import Foundation
import AppKit

/// Handles the core app switching logic for groups
@MainActor
class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()
    
    private init() {}
    
    /// Handle a shortcut activation for a given group
    func handleShortcut(for group: AppGroup, store: GroupStore) {
        let runningApps = getRunningApps(in: group)
        
        switch runningApps.count {
        case 0:
            // No apps running - launch the first app in the group
            if let firstApp = group.apps.first {
                launchApp(bundleIdentifier: firstApp.bundleIdentifier)
                store.updateLastActiveApp(bundleId: firstApp.bundleIdentifier, for: group.id)
            }
            
        case 1:
            // Only one app running - toggle between front and hidden
            let app = runningApps[0]
            if app.isActive {
                app.hide()
            } else {
                app.activate(options: .activateIgnoringOtherApps)
                store.updateLastActiveApp(bundleId: app.bundleIdentifier ?? "", for: group.id)
            }
            
        default:
            // Multiple apps running - cycle through them
            cycleApps(runningApps, group: group, store: store)
        }
    }
    
    /// Get all running apps that belong to a group
    private func getRunningApps(in group: AppGroup) -> [NSRunningApplication] {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        let groupBundleIds = Set(group.apps.map { $0.bundleIdentifier })
        
        return runningApps.filter { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return groupBundleIds.contains(bundleId) && app.activationPolicy == .regular
        }
    }
    
    /// Cycle through multiple running apps
    private func cycleApps(_ apps: [NSRunningApplication], group: AppGroup, store: GroupStore) {
        // Sort apps by their position in the group's app list
        let sortedApps = apps.sorted { app1, app2 in
            let index1 = group.apps.firstIndex { $0.bundleIdentifier == app1.bundleIdentifier } ?? Int.max
            let index2 = group.apps.firstIndex { $0.bundleIdentifier == app2.bundleIdentifier } ?? Int.max
            return index1 < index2
        }
        
        // Check if any app in the group is currently frontmost
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let isGroupAppActive = sortedApps.contains { $0.processIdentifier == frontmostApp?.processIdentifier }
        
        if isGroupAppActive {
            // Find the current app and switch to the next one
            if let currentIndex = sortedApps.firstIndex(where: { $0.processIdentifier == frontmostApp?.processIdentifier }) {
                let nextIndex = (currentIndex + 1) % sortedApps.count
                let nextApp = sortedApps[nextIndex]
                nextApp.activate(options: .activateIgnoringOtherApps)
                store.updateLastActiveApp(bundleId: nextApp.bundleIdentifier ?? "", for: group.id)
            }
        } else {
            // No group app is frontmost - bring the last used one, or first running
            let appToActivate: NSRunningApplication
            
            if let lastBundleId = group.lastActiveAppBundleId,
               let lastApp = sortedApps.first(where: { $0.bundleIdentifier == lastBundleId }) {
                appToActivate = lastApp
            } else {
                appToActivate = sortedApps[0]
            }
            
            appToActivate.activate(options: .activateIgnoringOtherApps)
            store.updateLastActiveApp(bundleId: appToActivate.bundleIdentifier ?? "", for: group.id)
        }
    }
    
    /// Launch an app by bundle identifier
    private func launchApp(bundleIdentifier: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            print("Could not find app with bundle identifier: \(bundleIdentifier)")
            return
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            if let error = error {
                print("Failed to launch app: \(error)")
            }
        }
    }
}

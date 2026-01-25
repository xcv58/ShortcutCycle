import SwiftUI

@main
struct AppShortcutsApp: App {
    @StateObject private var store = GroupStore()
    
    init() {
        // Request accessibility permission on first launch
        if !AccessibilityHelper.shared.hasAccessibilityPermission {
            AccessibilityHelper.shared.requestAccessibilityPermission()
        }
    }
    
    var body: some Scene {
        // Menu bar extra
        MenuBarExtra("App Shortcuts", systemImage: "command.square.fill") {
            MenuBarView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
        
        // Settings window
        Window("App Shortcuts", id: "settings") {
            MainView()
                .environmentObject(store)
                .onAppear {
                    setupShortcutManager()
                }
        }
        .defaultSize(width: 700, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
    
    private func setupShortcutManager() {
        Task { @MainActor in
            ShortcutManager.shared.setGroupStore(store)
            ShortcutManager.shared.registerAllShortcuts()
        }
    }
}

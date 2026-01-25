import SwiftUI

@main
struct ShortcutCycleApp: App {
    @StateObject private var store = GroupStore()
    @AppStorage("showDockIcon") private var showDockIcon = true
    
    init() {
        // Request accessibility permission on first launch
        if !AccessibilityHelper.shared.hasAccessibilityPermission {
            AccessibilityHelper.shared.requestAccessibilityPermission()
        }
    }
    
    var body: some Scene {
        // Menu bar extra
        MenuBarExtra("Shortcut Cycle", systemImage: "command.square.fill") {
            MenuBarView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
        
        // Settings window
        Window("Shortcut Cycle", id: "settings") {
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
        
        // Handle Dock icon visibility
        .onChange(of: showDockIcon) { _, newValue in
            updateActivationPolicy(showDockIcon: newValue)
        }
    }
    
    private func updateActivationPolicy(showDockIcon: Bool) {
        if showDockIcon {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        
        // If switching to regular, we might want to activate the app
        if showDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func setupShortcutManager() {
        Task { @MainActor in
            ShortcutManager.shared.setGroupStore(store)
            ShortcutManager.shared.registerAllShortcuts()
        }
    }
}

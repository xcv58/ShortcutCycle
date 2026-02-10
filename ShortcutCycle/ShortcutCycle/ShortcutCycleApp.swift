import SwiftUI
import KeyboardShortcuts
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif


@main
struct ShortcutCycleApp: App {
    @StateObject private var store = GroupStore.shared
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @StateObject private var localeObserver = LocaleObserver()
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Setup shortcut manager
        Task { @MainActor in
            ShortcutManager.shared.registerAllShortcuts()
        }
    }
    
    var body: some Scene {
        // Menu bar extra
        MenuBarExtra("Shortcut Cycle", systemImage: "command.square.fill") {
            MenuBarView(selectedLanguage: selectedLanguage)
                .environmentObject(store)
                .id("\(selectedLanguage)-\(localeObserver.id)") // Force redraw on language or system locale change
        }
        .menuBarExtraStyle(.window)
        
        // Settings window
        Window("Shortcut Cycle", id: "settings") {
            MainView()
                .environmentObject(store)
                .environmentObject(localeObserver)
                .onAppear {
                    // setupShortcutManager() called in init
                }
        }
        .defaultSize(width: 700, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
    

}


class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Run as a menu bar app (no dock icon)
        NSApp.setActivationPolicy(.accessory)
    }
}


// MARK: - Theme Manager

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    // For icon in menu
    var icon: String {
        switch self {
        case .system: return "display"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

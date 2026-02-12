import SwiftUI
import KeyboardShortcuts
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif


// MARK: - Focused Value Keys

struct SelectedTabKey: FocusedValueKey {
    typealias Value = Binding<String>
}

extension FocusedValues {
    var selectedTab: Binding<String>? {
        get { self[SelectedTabKey.self] }
        set { self[SelectedTabKey.self] = newValue }
    }
}

extension Notification.Name {
    static let deleteGroupRequested = Notification.Name("deleteGroupRequested")
}


// MARK: - App Commands

struct AppCommands: Commands {
    @FocusedBinding(\.selectedTab) private var selectedTab

    private var groupsDisabled: Bool {
        selectedTab != "groups" || GroupStore.shared.groups.count < 2
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Group") {
                selectedTab = "groups"
                GroupStore.shared.columnVisibility = .all
                GroupStore.shared.isAddingGroup = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(selectedTab == nil)

            Button("Delete Group") {
                NotificationCenter.default.post(name: .deleteGroupRequested, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedTab != "groups" || GroupStore.shared.selectedGroupId == nil)
        }

        CommandMenu("View") {
            Button("Toggle Sidebar") {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(selectedTab != "groups")

            Divider()

            Button("Groups") {
                selectedTab = "groups"
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(selectedTab == nil)

            Button("General") {
                selectedTab = "general"
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(selectedTab == nil)

            Divider()

            // Primary: arrow keys
            Button("Previous Group") {
                selectPreviousGroup()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(groupsDisabled)

            Button("Next Group") {
                selectNextGroup()
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(groupsDisabled)

            Divider()

            // Alternative: brackets
            Button("Previous Group") {
                selectPreviousGroup()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(groupsDisabled)

            Button("Next Group") {
                selectNextGroup()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(groupsDisabled)

            // Alternative: vim-style
            Button("Previous Group") {
                selectPreviousGroup()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(groupsDisabled)

            Button("Next Group") {
                selectNextGroup()
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(groupsDisabled)
        }
    }

    private func selectPreviousGroup() {
        let store = GroupStore.shared
        guard store.groups.count >= 2 else { return }
        guard let currentId = store.selectedGroupId,
              let currentIndex = store.groups.firstIndex(where: { $0.id == currentId }) else {
            store.selectedGroupId = store.groups.first?.id
            return
        }
        let previousIndex = currentIndex == 0 ? store.groups.count - 1 : currentIndex - 1
        store.selectedGroupId = store.groups[previousIndex].id
    }

    private func selectNextGroup() {
        let store = GroupStore.shared
        guard store.groups.count >= 2 else { return }
        guard let currentId = store.selectedGroupId,
              let currentIndex = store.groups.firstIndex(where: { $0.id == currentId }) else {
            store.selectedGroupId = store.groups.first?.id
            return
        }
        let nextIndex = currentIndex == store.groups.count - 1 ? 0 : currentIndex + 1
        store.selectedGroupId = store.groups[nextIndex].id
    }
}


// MARK: - Settings Window Observer

/// Switches activation policy back to .accessory when the settings window closes,
/// restoring the menu-bar-only appearance.
struct SettingsWindowObserver: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.observe(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class Coordinator {
        private var observer: NSObjectProtocol?

        func observe(window: NSWindow) {
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }

        deinit {
            if let o = observer {
                NotificationCenter.default.removeObserver(o)
            }
        }
    }
}


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
        }
        .defaultSize(width: 700, height: 500)
        .commands {
            AppCommands()
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

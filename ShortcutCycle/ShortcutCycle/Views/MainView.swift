
import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif


// MARK: - Main View

struct MainView: View {
    @EnvironmentObject var store: GroupStore
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @EnvironmentObject var localeObserver: LocaleObserver
    @State private var selectedTab = "groups"
    @State private var showDeleteConfirmation = false

    var body: some View {
        TabView(selection: $selectedTab) {
            GroupSettingsView()
                .tabItem {
                    Label("Groups".localized(language: selectedLanguage), systemImage: "rectangle.stack.3.hexagon")
                }
                .tag("groups")
            
            GeneralSettingsView()
                .tabItem {
                    Label("General".localized(language: selectedLanguage), systemImage: "gear")
                }
                .tag("general")
        }
        .focusedSceneValue(\.selectedTab, $selectedTab)
        .background(SettingsWindowObserver())
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteGroupRequested)) { _ in
            showDeleteConfirmation = true
        }
        .confirmationDialog(
            "Delete '\(store.selectedGroup?.name ?? "")'?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete".localized(language: selectedLanguage), role: .destructive) {
                if let group = store.selectedGroup {
                    store.deleteGroup(group)
                }
            }
            Button("Cancel".localized(language: selectedLanguage), role: .cancel) {}
        } message: {
            Text("This action cannot be undone.".localized(language: selectedLanguage))
        }
        .preferredColorScheme(appTheme.colorScheme)
        .frame(minWidth: 600, minHeight: 400)
        .environment(\.locale, LanguageManager.shared.locale)
        .id("\(selectedLanguage)-\(localeObserver.id)") // Force full redraw when language or system locale changes
    }
}

#Preview {
    MainView()
        .environmentObject(GroupStore.shared)
        .environmentObject(LocaleObserver())
}

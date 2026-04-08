
import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif


// MARK: - Main View

struct MainView: View {
    @EnvironmentObject var store: GroupStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @EnvironmentObject var localeObserver: LocaleObserver
    @State private var selectedTab = URLSettingsTab.groups.rawValue
    @State private var showDeleteConfirmation = false
    @AppStorage(WelcomeExperiencePolicy.hasDismissedWelcomeKey) private var hasDismissedWelcome = false

    var body: some View {
        VStack(spacing: 0) {
            if WelcomeExperiencePolicy.shouldShowBanner(hasDismissedWelcome: hasDismissedWelcome) {
                WelcomeBannerView(selectedLanguage: selectedLanguage) {
                    hasDismissedWelcome = true
                }
                .padding([.horizontal, .top])
            }

            TabView(selection: $selectedTab) {
                GroupSettingsView()
                    .tabItem {
                        Label("Groups".localized(language: selectedLanguage), systemImage: "square.grid.2x2")
                    }
                    .tag(URLSettingsTab.groups.rawValue)

                GeneralSettingsView()
                    .tabItem {
                        Label("General".localized(language: selectedLanguage), systemImage: "gear")
                    }
                    .tag(URLSettingsTab.general.rawValue)
            }
        }
        .focusedSceneValue(\.selectedTab, $selectedTab)
        .background(SettingsChromePalette.windowBackground(for: colorScheme))
        .background(SettingsWindowObserver())
        .onAppear {
            if let pendingTab = ShortcutCycleURLNavigationState.consumePendingSettingsTab() {
                selectedTab = pendingTab.rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteGroupRequested)) { _ in
            showDeleteConfirmation = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsTabRequested)) { notification in
            guard let raw = notification.object as? String,
                  let tab = URLSettingsTab(rawValue: raw) else {
                return
            }
            selectedTab = tab.rawValue
            ShortcutCycleURLNavigationState.markSettingsTabHandled(tab)
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
        .frame(minWidth: 720, minHeight: 460)
        .environment(\.locale, LanguageManager.shared.locale)
        .id("\(selectedLanguage)-\(localeObserver.id)") // Force full redraw when language or system locale changes
    }

}

#Preview {
    MainView()
        .environmentObject(GroupStore.shared)
        .environmentObject(LocaleObserver())
}

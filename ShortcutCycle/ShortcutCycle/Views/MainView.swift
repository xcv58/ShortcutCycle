
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
    // Observed (not owned) — WelcomeCoordinator.shared is an app-scoped singleton.
    @ObservedObject private var welcomeCoordinator = WelcomeCoordinator.shared
    // Transient welcome session: set on window open, cleared when the window closes.
    @State private var activeWelcomeRequestID: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            GroupSettingsView(welcomeRequestID: activeWelcomeRequestID)
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
            if let pendingTab = ShortcutCycleURLNavigationState.consumePendingSettingsTab() {
                selectedTab = pendingTab.rawValue
            }
            // Consume a pending welcome request queued before the window opened.
            consumeWelcomeRequest()
        }
        .onReceive(welcomeCoordinator.$pendingRequestID.compactMap { $0 }) { _ in
            // Consume a welcome request that arrived while the window is already open.
            consumeWelcomeRequest()
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
        .frame(minWidth: 600, minHeight: 400)
        .environment(\.locale, LanguageManager.shared.locale)
        .id("\(selectedLanguage)-\(localeObserver.id)") // Force full redraw when language or system locale changes
    }

    // MARK: - Private

    private func consumeWelcomeRequest() {
        guard let requestID = welcomeCoordinator.pendingRequestID else { return }
        selectedTab = "groups"
        activeWelcomeRequestID = requestID
        welcomeCoordinator.markRequestHandled(requestID)
    }
}

#Preview {
    MainView()
        .environmentObject(GroupStore.shared)
        .environmentObject(LocaleObserver())
}

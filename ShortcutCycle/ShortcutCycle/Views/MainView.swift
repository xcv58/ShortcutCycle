
import SwiftUI
import AppKit
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
    @State private var selectedTab = URLSettingsTab.groups.rawValue
    @State private var showDeleteConfirmation = false
    @AppStorage(WelcomeExperiencePolicy.hasDismissedWelcomeKey) private var hasDismissedWelcome = false
    @State private var hasDismissedSettingsShortcutHUDTip = false
    @State private var showSettingsShortcutHUDTip = false

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowAnyBanner {
                VStack(spacing: 8) {
                    if WelcomeExperiencePolicy.shouldShowBanner(hasDismissedWelcome: hasDismissedWelcome) {
                        WelcomeBannerView(selectedLanguage: selectedLanguage) {
                            hasDismissedWelcome = true
                        }
                    }

                    if shouldShowSettingsShortcutHUDTip {
                        SettingsShortcutHUDTipView(
                            selectedLanguage: selectedLanguage,
                            onCloseSettings: closeSettingsWindowFromTip,
                            onDismiss: dismissSettingsShortcutHUDTip
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: .settingsShortcutHUDTipRequested)) { _ in
            guard !hasDismissedSettingsShortcutHUDTip,
                  !showSettingsShortcutHUDTip else {
                return
            }

            withAnimation(.easeInOut(duration: 0.18)) {
                showSettingsShortcutHUDTip = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  SettingsWindowLifecycleCoordinator.isSettingsWindow(window) else {
                return
            }

            hasDismissedSettingsShortcutHUDTip = false
            showSettingsShortcutHUDTip = false
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
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .preferredColorScheme(appTheme.colorScheme)
        .background(WindowAppearanceApplier(colorScheme: appTheme.colorScheme))
        .frame(minWidth: 720, minHeight: 460)
        .environment(\.locale, LanguageManager.shared.locale)
        .id("\(selectedLanguage)-\(localeObserver.id)") // Force full redraw when language or system locale changes
    }

    private var shouldShowSettingsShortcutHUDTip: Bool {
        showSettingsShortcutHUDTip && !hasDismissedSettingsShortcutHUDTip
    }

    private var shouldShowAnyBanner: Bool {
        WelcomeExperiencePolicy.shouldShowBanner(hasDismissedWelcome: hasDismissedWelcome)
            || shouldShowSettingsShortcutHUDTip
    }

    private func dismissSettingsShortcutHUDTip() {
        hasDismissedSettingsShortcutHUDTip = true
        withAnimation(.easeInOut(duration: 0.18)) {
            showSettingsShortcutHUDTip = false
        }
    }

    private func closeSettingsWindowFromTip() {
        dismissSettingsShortcutHUDTip()
        NSApp.windows
            .first { SettingsWindowLifecycleCoordinator.isSettingsWindow($0) && $0.isVisible }?
            .close()
    }

}

#Preview {
    MainView()
        .environmentObject(GroupStore.shared)
        .environmentObject(LocaleObserver())
}

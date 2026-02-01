
import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers


// MARK: - Main View

struct MainView: View {
    @EnvironmentObject var store: GroupStore
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @State private var selectedTab = "groups"
    
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
        .preferredColorScheme(appTheme.colorScheme)
        .frame(minWidth: 600, minHeight: 400)
        .environment(\.locale, LanguageManager.shared.locale)
        .id(selectedLanguage) // Force full redraw when language changes
    }
}

#Preview {
    MainView()
        .environmentObject(GroupStore.shared)
}

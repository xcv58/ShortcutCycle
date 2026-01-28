import SwiftUI
import UniformTypeIdentifiers
import KeyboardShortcuts

/// Main settings window view with sidebar and detail
struct MainView: View {
    @EnvironmentObject var store: GroupStore
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
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
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            // No accessibility check needed
        }
        .environment(\.locale, LanguageManager.shared.locale)
        .id(selectedLanguage) // Force full redraw when language changes

    }
    

}

#Preview {
    MainView()
        .environmentObject(GroupStore.shared)
}

// MARK: - Subviews (Consolidated)

struct GroupSettingsView: View {
    @EnvironmentObject var store: GroupStore
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    
    var body: some View {
        NavigationSplitView {
            GroupListView()
                .frame(minWidth: 220)
        } detail: {
            if let selectedId = store.selectedGroupId {
                GroupEditView(groupId: selectedId)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No Group Selected".localized(language: selectedLanguage))
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Select a group from the sidebar or create a new one.".localized(language: selectedLanguage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("App Groups".localized(language: selectedLanguage))
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var store: GroupStore
    @AppStorage("showHUD") private var showHUD = true
    @AppStorage("showShortcutInHUD") private var showShortcutInHUD = true
    @StateObject private var launchAtLogin = LaunchAtLoginManager.shared
    
    // Derived language for localization updates
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    
    // Export/Import state
    @State private var showExportError = false
    @State private var showImportError = false
    @State private var showImportConfirmation = false
    @State private var showImportSuccess = false
    @State private var errorMessage = ""
    @State private var pendingImportURL: URL?
    
    var body: some View {
        Form {
            Section {
                // HUD Preview
                VStack(alignment: .center) {
                    HUDPreviewView(showShortcut: showShortcutInHUD, selectedLanguage: selectedLanguage)
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                        .opacity(showHUD ? 1.0 : 0.5) // Dim when disabled
                        .grayscale(showHUD ? 0.0 : 1.0) // Grayscale when disabled
                        .saturation(showHUD ? 1.0 : 0.0)
                        .overlay {
                            if !showHUD {
                                // optional: "Disabled" label overlay
                                Text("HUD Disabled".localized(language: selectedLanguage))
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.regularMaterial)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.bottom, 8)
                    
                    Text("Preview of the Heads-Up Display".localized(language: selectedLanguage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .listRowInsets(EdgeInsets())
                .padding()
                
                Toggle("Show HUD when switching".localized(language: selectedLanguage), isOn: $showHUD)
                
                if showHUD {
                    Toggle("Show shortcut in HUD".localized(language: selectedLanguage), isOn: $showShortcutInHUD)
                        .padding(.leading)
                    
                    Text("Displays the keyboard shortcut used to trigger the switch.".localized(language: selectedLanguage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading)
                }
            } header: {
                Text("HUD Behavior".localized(language: selectedLanguage))
            } footer: {
                Text("The HUD appears briefly when you cycle through applications in a group.".localized(language: selectedLanguage))
            }
            
            #if DEBUG
            Section {
                HStack {
                    Text("Settings Window".localized(language: selectedLanguage))
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleSettings)
                }
            } header: {
                Text("Shortcuts".localized(language: selectedLanguage))
            }
            #endif
            
            Section {
                Toggle("Open at Login".localized(language: selectedLanguage), isOn: $launchAtLogin.isEnabled)
                    .toggleStyle(.switch)
                
                Picker("Language".localized(language: selectedLanguage), selection: Binding(
                    get: { UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system" },
                    set: { newValue in
                        UserDefaults.standard.set(newValue, forKey: "selectedLanguage")
                    }
                )) {
                    Text("\("System Default".localized(language: "system")) (\(Locale.current.language.languageCode?.identifier ?? "en"))").tag("system")
                    ForEach(LanguageManager.shared.supportedLanguages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                .pickerStyle(.menu)
                
                if selectedLanguage != "system" {
                    Text("May require restart to take effect fully.".localized(language: selectedLanguage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Application".localized(language: selectedLanguage))
            }
            
            Section {
                HStack {
                    Button("Export Settings...".localized(language: selectedLanguage)) {
                        exportSettings()
                    }
                    
                    Button("Import Settings...".localized(language: selectedLanguage)) {
                        importSettings()
                    }
                }
            } header: {
                Text("Backup & Restore".localized(language: selectedLanguage))
            } footer: {
                Text("Export your groups and settings to a JSON file for backup or transfer to another Mac.".localized(language: selectedLanguage))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General".localized(language: selectedLanguage))
        .alert("Export Failed".localized(language: selectedLanguage), isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Import Failed".localized(language: selectedLanguage), isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Import Settings?".localized(language: selectedLanguage), isPresented: $showImportConfirmation) {
            Button("Cancel".localized(language: selectedLanguage), role: .cancel) {
                pendingImportURL = nil
            }
            Button("Import".localized(language: selectedLanguage), role: .destructive) {
                performImport()
            }
        } message: {
            Text("This will replace all your current groups and settings. This action cannot be undone.".localized(language: selectedLanguage))
        }
        .alert("Import Successful".localized(language: selectedLanguage), isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your settings have been imported successfully.".localized(language: selectedLanguage))
        }
    }
    
    // MARK: - Export/Import Actions
    
    private func exportSettings() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "ShortcutCycle-Settings.json"
        savePanel.title = "Export Settings".localized(language: selectedLanguage)
        savePanel.message = "Choose where to save your settings".localized(language: selectedLanguage)
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            do {
                let data = try store.exportData()
                try data.write(to: url)
            } catch {
                errorMessage = error.localizedDescription
                showExportError = true
            }
        }
    }
    
    private func importSettings() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.title = "Import Settings".localized(language: selectedLanguage)
        openPanel.message = "Select a ShortcutCycle settings file".localized(language: selectedLanguage)
        
        openPanel.begin { response in
            guard response == .OK, let url = openPanel.url else { return }
            pendingImportURL = url
            showImportConfirmation = true
        }
    }
    
    private func performImport() {
        guard let url = pendingImportURL else { return }
        
        do {
            let data = try Data(contentsOf: url)
            try store.importData(data)
            showImportSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showImportError = true
        }
        
        pendingImportURL = nil
    }
}

/// A static preview of the HUD for settings
struct HUDPreviewView: View {
    let showShortcut: Bool
    var selectedLanguage: String = "system"
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            // Icons Row
            HStack(spacing: 16) {
                // Mock icons
                Image(systemName: "safari.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundColor(.blue)
                    .padding(8)
                    .opacity(0.6)
                
                Image(systemName: "message.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundColor(.green)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .scaleEffect(1.1)
                
                Image(systemName: "envelope.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundColor(.blue)
                    .padding(8)
                    .opacity(0.6)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            
            // App Name Label
            VStack(spacing: 2) {
                Text("Messages")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if showShortcut {
                    Text("⌃ ⌥ ⌘  C")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.regularMaterial)
            )
        }
    }
}

// MARK: - HUD Views

struct HUDAppItem: Identifiable, Equatable {
    let id: String // Bundle ID
    let name: String
    let icon: NSImage?
    let isRunning: Bool
    
    // For Equatable
    static func == (lhs: HUDAppItem, rhs: HUDAppItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct AppSwitcherHUDView: View {
    let apps: [HUDAppItem]
    let activeAppId: String
    let shortcutString: String?
    
    @AppStorage("showShortcutInHUD") private var showShortcutInHUD = true
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            // Icons Row
            HStack(spacing: 20) {
                ForEach(apps) { app in
                    if let icon = app.icon {
                        HUDItemView(icon: icon, isActive: app.id == activeAppId, isRunning: app.isRunning)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    // Adaptive tint based on color scheme
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.3))
                    )
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            
            // Active App Name
            VStack(spacing: 4) {
                if let activeApp = apps.first(where: { $0.id == activeAppId }) {
                    Text(activeApp.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundColor(.primary)
                }
                
                if showShortcutInHUD, let shortcut = shortcutString {
                    Text(shortcut)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
        }
        .padding(40)
    }
}

struct HUDItemView: View {
    let icon: NSImage
    let isActive: Bool
    let isRunning: Bool
    
    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 72, height: 72)
            .scaleEffect(isActive ? 1.15 : 1.0)
            .saturation(isActive ? 1.1 : (isRunning ? 0.8 : 0.2)) // Grayscale if not running
            .opacity(isActive ? 1.0 : (isRunning ? 0.7 : 0.5)) // Dimmer if not running
            .blur(radius: 0)
            .overlay(alignment: .bottomTrailing) {
                 if !isRunning {
                     Image(systemName: "arrow.up.circle.fill")
                         .font(.system(size: 20))
                         .foregroundColor(.white)
                         .background(Circle().fill(Color.blue))
                         .offset(x: 4, y: 4)
                         .shadow(radius: 2)
                 }
            }
            .padding(12)
            .background(
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                        
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 0)
                    }
                }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - Language Helper

class LanguageManager {
    static let shared = LanguageManager()
    
    struct Language {
        let code: String
        let name: String
    }
    
    let supportedLanguages = [
        Language(code: "en", name: "English"),
        Language(code: "de", name: "Deutsch"),
        Language(code: "fr", name: "Français"),
        Language(code: "es", name: "Español"),
        Language(code: "ja", name: "日本語"),
        Language(code: "pt-BR", name: "Português (Brasil)"),
        Language(code: "zh-Hans", name: "简体中文"),
        Language(code: "zh-Hant", name: "繁體中文"),
        Language(code: "it", name: "Italiano"),
        Language(code: "ko", name: "한국어"),
        Language(code: "ar", name: "العربية"),
        Language(code: "nl", name: "Nederlands"),
        Language(code: "pl", name: "Polski"),
        Language(code: "tr", name: "Türkçe"),
        Language(code: "ru", name: "Русский")
    ]
    
    var locale: Locale {
        let selected = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system"
        if selected == "system" {
            return Locale.current
        }
        return Locale(identifier: selected)
    }
}

// MARK: - String Localization Helper

extension String {
    func localized(language: String) -> String {
        let selectedLanguage = language == "system" ? Locale.current.language.languageCode?.identifier : language
        
        guard let code = selectedLanguage,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(self, comment: "")
        }
        
        return NSLocalizedString(self, tableName: nil, bundle: bundle, value: "", comment: "")
    }
}

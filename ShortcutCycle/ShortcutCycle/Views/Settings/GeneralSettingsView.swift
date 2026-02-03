import SwiftUI
import KeyboardShortcuts
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

struct GeneralSettingsView: View {
    @EnvironmentObject var store: GroupStore
    @AppStorage("showHUD") private var showHUD = true
    @AppStorage("showShortcutInHUD") private var showShortcutInHUD = true
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
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

    // Backup browser state
    @State private var showBackupBrowser = false
    @State private var manualBackupFeedback: String?

    // Clipboard state
    @State private var showClipboardImportConfirmation = false
    @State private var showClipboardImportSuccess = false
    @State private var showClipboardError = false
    @State private var clipboardErrorMessage = ""
    @State private var clipboardImportSummary = ""
    @State private var pendingClipboardExport: SettingsExport?
    
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
                
                Picker("Appearance".localized(language: selectedLanguage), selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName.localized(language: selectedLanguage)).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                
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
                
                if selectedLanguage != "system" && selectedLanguage != Locale.current.language.languageCode?.identifier {
                    Text("May require restart to take effect fully.".localized(language: selectedLanguage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Application".localized(language: selectedLanguage))
            }
            
            Section {
                // Sub-section 1: File-based backup
                VStack(alignment: .leading, spacing: 8) {
                    Label("File Export/Import".localized(language: selectedLanguage), systemImage: "doc.badge.gearshape")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    HStack {
                        Button("Export Settings...".localized(language: selectedLanguage)) {
                            exportSettings()
                        }

                        Button("Import Settings...".localized(language: selectedLanguage)) {
                            importSettings()
                        }
                    }
                    Text("Save to or load from a JSON file.".localized(language: selectedLanguage))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                
                // Sub-section 2: Clipboard-based sync
                VStack(alignment: .leading, spacing: 8) {
                    Label("Clipboard Sync".localized(language: selectedLanguage), systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    HStack {
                        Button("Copy to Clipboard".localized(language: selectedLanguage)) {
                            copySettingsToClipboard()
                        }

                        Button("Paste from Clipboard".localized(language: selectedLanguage)) {
                            pasteSettingsFromClipboard()
                        }
                    }
                    Text("Use Universal Clipboard to sync between Macs.".localized(language: selectedLanguage))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Sub-section 3: Automatic Backups
                VStack(alignment: .leading, spacing: 8) {
                    Label("Automatic Backups".localized(language: selectedLanguage), systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    HStack {
                        Button("View Automatic Backups...".localized(language: selectedLanguage)) {
                            showBackupBrowser = true
                        }
                        Button("Back Up Now".localized(language: selectedLanguage)) {
                            performManualBackup()
                        }
                    }
                    if let feedback = manualBackupFeedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: manualBackupFeedback)
                    }
                    Text("View and restore from automatic backups.".localized(language: selectedLanguage))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Backup & Restore".localized(language: selectedLanguage))
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
        .alert("Clipboard Error".localized(language: selectedLanguage), isPresented: $showClipboardError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(clipboardErrorMessage)
        }
        .alert("Paste Settings?".localized(language: selectedLanguage), isPresented: $showClipboardImportConfirmation) {
            Button("Cancel".localized(language: selectedLanguage), role: .cancel) {
                pendingClipboardExport = nil
            }
            Button("Import".localized(language: selectedLanguage), role: .destructive) {
                performClipboardImport()
            }
        } message: {
            Text(clipboardImportSummary)
        }
        .sheet(isPresented: $showBackupBrowser) {
            BackupBrowserView()
                .environmentObject(store)
        }
        .alert("Import Successful".localized(language: selectedLanguage), isPresented: $showClipboardImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your settings have been imported from clipboard.".localized(language: selectedLanguage))
        }
    }
    
    // MARK: - Export/Import Actions
    
    private func exportSettings() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "ShortcutCycle-Settings \(timestamp).json"
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

    // MARK: - Clipboard Actions

    private func copySettingsToClipboard() {
        do {
            let data = try store.exportData()
            guard let jsonString = String(data: data, encoding: .utf8) else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(jsonString, forType: .string)
        } catch {
            clipboardErrorMessage = error.localizedDescription
            showClipboardError = true
        }
    }

    private func pasteSettingsFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let string = pasteboard.string(forType: .string), !string.isEmpty else {
            clipboardErrorMessage = "No text found on clipboard.".localized(language: selectedLanguage)
            showClipboardError = true
            return
        }

        guard let data = string.data(using: .utf8) else {
            clipboardErrorMessage = "Clipboard content is not valid text.".localized(language: selectedLanguage)
            showClipboardError = true
            return
        }

        switch SettingsExport.validate(data: data) {
        case .success(let export):
            pendingClipboardExport = export
            clipboardImportSummary = String(
                format: "This will import %d group(s) and replace all current settings. This action cannot be undone.".localized(language: selectedLanguage),
                export.groups.count
            )
            showClipboardImportConfirmation = true
        case .failure(let error):
            clipboardErrorMessage = error.localizedDescription
            showClipboardError = true
        }
    }

    private func performManualBackup() {
        let result = store.manualBackup()
        switch result {
        case .saved:
            manualBackupFeedback = "Backed up successfully".localized(language: selectedLanguage)
        case .noChange:
            manualBackupFeedback = "No changes to save".localized(language: selectedLanguage)
        case .error(let msg):
            manualBackupFeedback = String(format: "Backup failed: %@".localized(language: selectedLanguage), msg)
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            manualBackupFeedback = nil
        }
    }

    private func performClipboardImport() {
        guard let export = pendingClipboardExport else { return }
        store.applyImport(export)
        showClipboardImportSuccess = true
        pendingClipboardExport = nil
    }
}

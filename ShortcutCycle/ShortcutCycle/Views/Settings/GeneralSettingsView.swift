import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

struct GeneralSettingsView: View {
    @EnvironmentObject var store: GroupStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showHUD") private var showHUD = true
    @AppStorage("showShortcutInHUD") private var showShortcutInHUD = true
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage(WelcomeExperiencePolicy.hasDismissedWelcomeKey) private var hasDismissedWelcome = false
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
    @State private var hostingWindow: NSWindow?

    // Backup browser state
    @State private var showBackupBrowser = false
    @State private var manualBackupFeedback: String?
    @State private var showShortcutReferencePopover = false
    @State private var settingsShortcutRefreshToken = 0
    @ObservedObject private var appDistribution = AppDistributionMonitor.shared

    // Clipboard state
    @State private var showClipboardImportConfirmation = false
    @State private var showClipboardImportSuccess = false
    @State private var showClipboardError = false
    @State private var clipboardErrorMessage = ""
    @State private var clipboardImportSummary = ""
    @State private var pendingClipboardExport: SettingsExport?

    #if DEBUG
    private var isScreenshotMode: Bool {
        ScreenshotMode.usesSyntheticControls
    }
    #endif

    var body: some View {
        content
        .background(SettingsWindowAccessor(window: $hostingWindow))
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
        .onAppear {
            if ShortcutCycleURLNavigationState.consumePendingBackupBrowser() {
                showBackupBrowser = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .backupBrowserRequested)) { _ in
            showBackupBrowser = true
            ShortcutCycleURLNavigationState.markBackupBrowserHandled()
        }
        .alert("Import Successful".localized(language: selectedLanguage), isPresented: $showClipboardImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your settings have been imported from clipboard.".localized(language: selectedLanguage))
        }
    }

    private var content: some View {
        Form {
            Section {
                VStack(alignment: .center) {
                    HUDPreviewView(showShortcut: showShortcutInHUD, selectedLanguage: selectedLanguage)
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    colorScheme == .dark
                                        ? SettingsChromePalette.panelBackground(for: colorScheme)
                                        : Color.black.opacity(0.05)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    colorScheme == .dark
                                        ? SettingsChromePalette.panelBorder(for: colorScheme)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .opacity(showHUD ? 1.0 : 0.5)
                        .grayscale(showHUD ? 0.0 : 1.0)
                        .saturation(showHUD ? 1.0 : 0.0)
                        .overlay {
                            if !showHUD {
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

                #if DEBUG
                if isScreenshotMode {
                    screenshotToggleRow("Show HUD when switching".localized(language: selectedLanguage), isOn: showHUD)
                } else {
                    Toggle("Show HUD when switching".localized(language: selectedLanguage), isOn: $showHUD)
                        .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                        .tint(.accentColor)
                }
                #else
                Toggle("Show HUD when switching".localized(language: selectedLanguage), isOn: $showHUD)
                    .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                    .tint(.accentColor)
                #endif

                if showHUD {
                    #if DEBUG
                    if isScreenshotMode {
                        screenshotToggleRow("Show shortcut in HUD".localized(language: selectedLanguage), isOn: showShortcutInHUD)
                            .padding(.leading)
                    } else {
                        Toggle("Show shortcut in HUD".localized(language: selectedLanguage), isOn: $showShortcutInHUD)
                            .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                            .tint(.accentColor)
                            .padding(.leading)
                    }
                    #else
                    Toggle("Show shortcut in HUD".localized(language: selectedLanguage), isOn: $showShortcutInHUD)
                        .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                        .tint(.accentColor)
                        .padding(.leading)
                    #endif

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

            Section {
                if shouldShowDistributionStatus,
                   let titleKey = appDistribution.channel.titleKey,
                   let detailKey = appDistribution.channel.detailKey,
                   let symbolName = appDistribution.channel.symbolName {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbolName)
                            .foregroundStyle(appDistribution.channel.usesWarningColor ? .orange : Color.accentColor)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(titleKey.localized(language: selectedLanguage))
                                .font(.subheadline.weight(.semibold))
                            Text(detailKey.localized(language: selectedLanguage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                #if DEBUG
                if isScreenshotMode {
                    screenshotToggleRow("Open at Login".localized(language: selectedLanguage), isOn: launchAtLogin.isEnabled)
                } else {
                    Toggle("Open at Login".localized(language: selectedLanguage), isOn: $launchAtLogin.isEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                        .tint(.accentColor)
                }
                #else
                Toggle("Open at Login".localized(language: selectedLanguage), isOn: $launchAtLogin.isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                    .tint(.accentColor)
                #endif

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
                        LanguageManager.shared.syncAppleLanguages(for: newValue)
                    }
                )) {
                    Text("\("System Default".localized(language: "system")) (\(LanguageManager.shared.supportedLanguages.first { $0.code == LanguageManager.shared.systemLanguageCode }?.name ?? "English"))").tag("system")
                    ForEach(LanguageManager.shared.supportedLanguages, id: \.code) { language in
                        Text(language.displayName(in: LanguageManager.shared.locale)).tag(language.code)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent {
                    LocalizedKeyboardShortcutRecorder(
                        name: .toggleSettings,
                        selectedLanguage: selectedLanguage,
                        onRecord: recordSettingsWindowShortcut,
                        onBeginRecording: suspendGlobalShortcuts,
                        onEndRecording: resumeGlobalShortcuts
                    )
                } label: {
                    Text("Settings Window".localized(language: selectedLanguage))
                }
                .id("settings-window-shortcut-\(selectedLanguage)-\(settingsShortcutRefreshToken)")

                Button {
                    showShortcutReferencePopover = true
                } label: {
                    HStack {
                        Label("Shortcuts".localized(language: selectedLanguage), systemImage: "keyboard")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(.tertiary)
                    }
                }
                .popover(isPresented: $showShortcutReferencePopover, arrowEdge: .bottom) {
                    KeyboardShortcutReferencePopover(selectedLanguage: selectedLanguage)
                }

                if WelcomeExperiencePolicy.shouldShowReplayControl(hasDismissedWelcome: hasDismissedWelcome) {
                    Button("Show welcome again".localized(language: selectedLanguage)) {
                        WelcomeExperiencePolicy.prepareReplay()
                        ShortcutCycleURLRouter.openSettingsFromOutsideView(tab: .groups)
                    }
                }

            } header: {
                Text("Application".localized(language: selectedLanguage))
            }

            Section {
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
        .scrollContentBackground(colorScheme == .dark ? .hidden : .automatic)
        .background(SettingsChromePalette.windowBackground(for: colorScheme))
    }

    private var shouldShowDistributionStatus: Bool {
        #if DEBUG
        !isScreenshotMode && appDistribution.channel != .appStore
        #else
        appDistribution.channel != .appStore
        #endif
    }

    #if DEBUG
    private func screenshotToggleRow(_ title: String, isOn: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            ScreenshotAccentSwitch(isOn: isOn)
        }
    }
    #endif

    @MainActor
    private func recordSettingsWindowShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) -> ShortcutRecorderRecordingResult {
        if let shortcut,
           let conflict = ShortcutAssignmentConflicts.conflict(
               for: shortcut,
               assigning: .settingsWindow,
               groups: store.groups
           ) {
            return .rejected(conflict.message { $0.localized(language: selectedLanguage) })
        }

        KeyboardShortcuts.setShortcut(shortcut, for: .toggleSettings)
        refreshSettingsShortcutState()
        return .accepted
    }

    @MainActor
    private func suspendGlobalShortcuts() {
        ShortcutManager.shared.suspendForShortcutRecording()
    }

    @MainActor
    private func resumeGlobalShortcuts() {
        ShortcutManager.shared.resumeAfterShortcutRecording()
    }

    @MainActor
    private func refreshSettingsShortcutState() {
        settingsShortcutRefreshToken += 1
        ShortcutManager.shared.registerAllShortcuts()
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
        
        presentPanel(savePanel) { response in
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
        
        presentPanel(openPanel) { response in
            guard response == .OK, let url = openPanel.url else { return }
            pendingImportURL = url
            showImportConfirmation = true
        }
    }

    private func presentPanel(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = panelPresentationWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private var panelPresentationWindow: NSWindow? {
        if let hostingWindow {
            return hostingWindow
        }

        return SettingsWindowLifecycleCoordinator.anyVisibleSettingsWindow(in: NSApp.windows)
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

private struct SettingsWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = AccessorView()
        view.onWindowChange = { newWindow in
            window = newWindow
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let accessorView = nsView as? AccessorView else { return }
        accessorView.onWindowChange = { newWindow in
            window = newWindow
        }
    }

    private final class AccessorView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.onWindowChange?(self?.window)
            }
        }
    }
}

private struct KeyboardShortcutReferencePopover: View {
    let selectedLanguage: String

    private var shortcutReferences: [(title: String, shortcuts: [String])] {
        [
            ("Settings...".localized(language: selectedLanguage), ["⌘ + ,"]),
            ("Toggle Appearance".localized(language: selectedLanguage), ["⌃ + ⌘ + A"]),
            ("Groups".localized(language: selectedLanguage), ["⌘ + 1"]),
            ("General".localized(language: selectedLanguage), ["⌘ + 2"]),
            ("Add Group".localized(language: selectedLanguage), ["⌘ + N"]),
            ("Delete Group".localized(language: selectedLanguage), ["⌘ + ⌫"]),
            ("Toggle Sidebar".localized(language: selectedLanguage), ["⌃ + ⌘ + S"]),
            ("Previous Group".localized(language: selectedLanguage), ["⌘ + ↑", "⌘ + [", "⌘ + K"]),
            ("Next Group".localized(language: selectedLanguage), ["⌘ + ↓", "⌘ + ]", "⌘ + J"]),
            ("Move Group Up".localized(language: selectedLanguage), ["⌥ + ⌘ + ↑"]),
            ("Move Group Down".localized(language: selectedLanguage), ["⌥ + ⌘ + ↓"])
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shortcuts".localized(language: selectedLanguage))
                .font(.headline)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(shortcutReferences.enumerated()), id: \.offset) { _, item in
                        KeyboardShortcutReferenceRow(
                            title: item.title,
                            shortcuts: item.shortcuts,
                            selectedLanguage: selectedLanguage
                        )
                    }
                }
                .padding(.trailing, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 420, height: 300)
    }
}

private struct KeyboardShortcutReferenceRow: View {
    let title: String
    let shortcuts: [String]
    let selectedLanguage: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    KeyboardShortcutBadge(shortcut: shortcut)

                    if index < shortcuts.count - 1 {
                        Text("or".localized(language: selectedLanguage))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

enum KeyboardShortcutGlyphLayout {
    static func components(in shortcut: String) -> [String] {
        shortcut.components(separatedBy: " + ")
    }
}

private struct KeyboardShortcutBadge: View {
    let shortcut: String

    private var components: [String] {
        KeyboardShortcutGlyphLayout.components(in: shortcut)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                Text(component)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()

                if index < components.count - 1 {
                    Text("+")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut)
    }
}

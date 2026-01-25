
import SwiftUI
import UniformTypeIdentifiers

/// Main settings window view with sidebar and detail
struct MainView: View {
    @EnvironmentObject var store: GroupStore
    @State private var showAccessibilityAlert = false
    
    var body: some View {
        TabView {
            GroupSettingsView()
                .tabItem {
                    Label("Groups", systemImage: "rectangle.stack.3.hexagon")
                }
            
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            checkAccessibility()
        }
        .alert("Accessibility Permission Required", isPresented: $showAccessibilityAlert) {
            Button("Open System Preferences") {
                AccessibilityHelper.shared.openAccessibilityPreferences()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("ShortcutCycle needs accessibility permission to register global keyboard shortcuts and switch between applications.")
        }
    }
    
    private func checkAccessibility() {
        if !AccessibilityHelper.shared.hasAccessibilityPermission {
            showAccessibilityAlert = true
        }
    }
}

#Preview {
    MainView()
        .environmentObject(GroupStore())
}

// MARK: - Subviews (Consolidated)

struct GroupSettingsView: View {
    @EnvironmentObject var store: GroupStore
    
    var body: some View {
        NavigationSplitView {
            GroupListView()
                .frame(minWidth: 200)
        } detail: {
            if let selectedId = store.selectedGroupId {
                GroupEditView(groupId: selectedId)
            } else {
                ContentUnavailableView(
                    "No Group Selected",
                    systemImage: "folder",
                    description: Text("Select a group from the sidebar or create a new one.")
                )
            }
        }
        .navigationTitle("App Groups")
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var store: GroupStore
    @AppStorage("showHUD") private var showHUD = true
    @AppStorage("showShortcutInHUD") private var showShortcutInHUD = true
    @AppStorage("showDockIcon") private var showDockIcon = true
    @StateObject private var launchAtLogin = LaunchAtLoginManager.shared
    // @StateObject private var cloudSync = CloudSyncManager.shared // Temporarily disabled
    
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
                    HUDPreviewView(showShortcut: showShortcutInHUD)
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
                                Text("HUD Disabled")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.regularMaterial)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.bottom, 8)
                    
                    Text("Preview of the Heads-Up Display")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .listRowInsets(EdgeInsets())
                .padding()
                
                Toggle("Show HUD when switching", isOn: $showHUD)
                
                if showHUD {
                    Toggle("Show shortcut in HUD", isOn: $showShortcutInHUD)
                        .padding(.leading)
                    
                    Text("Displays the keyboard shortcut used to trigger the switch.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading)
                }
            } header: {
                Text("HUD Behavior")
            } footer: {
                Text("The HUD appears briefly when you cycle through applications in a group.")
            }
            
            Section {
                Toggle("Open at Login", isOn: $launchAtLogin.isEnabled)
                    .toggleStyle(.switch)
                
                Toggle(isOn: $showDockIcon) {
                    VStack(alignment: .leading) {
                        Text("Show Icon in Dock")
                        if !showDockIcon {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("May require restart to take effect")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Application")
            } footer: {
                Text("Hiding the dock icon makes the app run in the background (Accessory mode).")
            }
            
            Section {
                HStack {
                    Button("Export Settings...") {
                        exportSettings()
                    }
                    
                    Button("Import Settings...") {
                        importSettings()
                    }
                }
            } header: {
                Text("Backup & Restore")
            } footer: {
                Text("Export your groups and settings to a JSON file for backup or transfer to another Mac.")
            }
            
            // MARK: - iCloud Sync (Temporarily Disabled)
            // Uncomment when Apple Developer account is renewed
            /*
            Section {
                Toggle("Sync with iCloud", isOn: $cloudSync.isSyncEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: cloudSync.isSyncEnabled) { _, newValue in
                        if newValue {
                            cloudSync.setGroupStore(store)
                        }
                    }
                
                if cloudSync.isSyncEnabled {
                    HStack {
                        if cloudSync.isSyncing {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Syncing...")
                                .foregroundColor(.secondary)
                        } else if let lastSync = cloudSync.lastSyncDate {
                            Text("Last synced: \(lastSync, style: .relative) ago")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        Button("Sync Now") {
                            cloudSync.syncNow()
                        }
                        .disabled(cloudSync.isSyncing)
                    }
                    
                    if let error = cloudSync.syncError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text("Automatically sync your groups across all your Macs signed into the same iCloud account.")
            }
            */
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        // .onAppear { cloudSync.setGroupStore(store) } // Temporarily disabled
        .onChange(of: showDockIcon) { _, newValue in
            if newValue {
                NSApp.setActivationPolicy(.regular)
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Import Settings?", isPresented: $showImportConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
            Button("Import", role: .destructive) {
                performImport()
            }
        } message: {
            Text("This will replace all your current groups and settings. This action cannot be undone.")
        }
        .alert("Import Successful", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your settings have been imported successfully.")
        }
    }
    
    // MARK: - Export/Import Actions
    
    private func exportSettings() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "ShortcutCycle-Settings.json"
        savePanel.title = "Export Settings"
        savePanel.message = "Choose where to save your settings"
        
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
        openPanel.title = "Import Settings"
        openPanel.message = "Select a ShortcutCycle settings file"
        
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

struct AppSwitcherHUDView: View {
    let apps: [NSRunningApplication]
    let activeApp: NSRunningApplication
    let shortcutString: String?
    
    @AppStorage("showShortcutInHUD") private var showShortcutInHUD = true
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            // Icons Row
            HStack(spacing: 20) {
                ForEach(apps, id: \.processIdentifier) { app in
                    if let icon = app.icon {
                        HUDItemView(icon: icon, isActive: isActive(app))
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
                Text(activeApp.localizedName ?? "App")
                    .font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundColor(.primary)
                
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
    
    private func isActive(_ app: NSRunningApplication) -> Bool {
        return app.processIdentifier == activeApp.processIdentifier
    }
}

struct HUDItemView: View {
    let icon: NSImage
    let isActive: Bool
    
    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 72, height: 72)
            .scaleEffect(isActive ? 1.15 : 1.0)
            .saturation(isActive ? 1.1 : 0.8)
            .opacity(isActive ? 1.0 : 0.7)
            .blur(radius: 0)
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

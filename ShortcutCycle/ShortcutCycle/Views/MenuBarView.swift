import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif
import KeyboardShortcuts

/// Menu bar popover view showing quick access to groups
struct MenuBarView: View {
    @EnvironmentObject var store: GroupStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var launchAtLogin = LaunchAtLoginManager.shared
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    
    var selectedLanguage: String = "system"
    
    @State private var listHeight: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("ShortcutCycle")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            Divider()
            
            // Groups list
            ScrollView {
                VStack(spacing: 0) {
                    if store.groups.isEmpty {
                        Text("No groups created yet".localized(language: selectedLanguage))
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(store.groups) { group in
                            MenuBarGroupRow(group: group)
                        }
                    }
                }
                .background(
                    GeometryReader { geo in
                         Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
                    }
                )
            }
            .frame(height: listHeight > 0 ? min(listHeight, 800) : nil)
            .onPreferenceChange(HeightPreferenceKey.self) { height in
                listHeight = height
            }
            
            Divider()
            
            // Preferences
            Toggle("Open at Login".localized(language: selectedLanguage), isOn: $launchAtLogin.isEnabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            
            Divider()
                .padding(.vertical, 4)
            
            // Theme selection
            HStack(spacing: 0) {
                Text("Appearance".localized(language: selectedLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
                
                Spacer()
                
                HStack(spacing: 2) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            appTheme = theme
                        } label: {
                            Image(systemName: theme.icon)
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(appTheme == theme ? Color.accentColor : Color.clear)
                                .foregroundColor(appTheme == theme ? .white : .primary)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(theme.displayName.localized(language: selectedLanguage))
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 4)
            
            Divider()
                .padding(.vertical, 4)
            
            // Settings button
            MenuBarButton(title: "Settings...".localized(language: selectedLanguage), icon: "gear") {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            
            MenuBarButton(title: "Quit".localized(language: selectedLanguage), icon: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 280)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .background(WindowAppearanceApplier(colorScheme: appTheme.colorScheme))
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleSettingsWindow"))) { _ in
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .preferredColorScheme(appTheme.colorScheme)
    }
}

/// A generic menu bar button with hover effect
struct MenuBarButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.accentColor : Color.clear)
        .foregroundColor(isHovering ? .white : .primary)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// A single group row in the menu bar view
struct MenuBarGroupRow: View {
    let group: AppGroup
    @EnvironmentObject var store: GroupStore
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Enable/Disable Toggle
            Toggle("", isOn: Binding(
                get: { group.isEnabled },
                set: { _ in store.toggleGroupEnabled(group) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            
            Image(systemName: "folder.fill")
                .foregroundColor(group.isEnabled ? (isHovering ? .white : .accentColor) : .gray)
            
            Text(group.name)
                .foregroundColor(group.isEnabled ? (isHovering ? .white : .primary) : .secondary)
            
            Spacer()
            
            if let shortcutString = group.shortcutDisplayString {
                Text(shortcutString)
                    .font(.caption)
                    .foregroundColor(isHovering ? .white.opacity(0.8) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        isHovering ? Color.white.opacity(0.2) : Color.gray.opacity(0.1)
                    )
                    .cornerRadius(4)
            }
            
            // Show running app count
            let runningCount = countRunningApps(in: group)
            if runningCount > 0 {
                Circle()
                    .fill(group.isEnabled ? (isHovering ? .white : Color.green) : Color.gray)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isHovering ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func countRunningApps(in group: AppGroup) -> Int {
        let runningApps = NSWorkspace.shared.runningApplications
        let groupBundleIds = Set(group.apps.map { $0.bundleIdentifier })
        
        return runningApps.filter { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return groupBundleIds.contains(bundleId) && app.activationPolicy == .regular
        }.count
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

#Preview {
    MenuBarView()
        .environmentObject(GroupStore.shared)
}

struct WindowAppearanceApplier: NSViewRepresentable {
    var colorScheme: ColorScheme?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            updateWindowAppearance(for: view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            updateWindowAppearance(for: nsView)
        }
    }
    
    private func updateWindowAppearance(for view: NSView) {
        guard let window = view.window else { return }
        
        if let colorScheme = colorScheme {
            window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        } else {
            window.appearance = nil // Reset to system
        }
    }
}

struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}



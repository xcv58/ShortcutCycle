import SwiftUI
import KeyboardShortcuts

/// Menu bar popover view showing quick access to groups
struct MenuBarView: View {
    @EnvironmentObject var store: GroupStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var launchAtLogin = LaunchAtLoginManager.shared
    
    var selectedLanguage: String = "system"
    
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
            
            Divider()
            
            // Preferences
            Toggle("Open at Login".localized(language: selectedLanguage), isOn: $launchAtLogin.isEnabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            
            Divider()
            
            // Settings button
            MenuBarButton(title: "Settings...".localized(language: selectedLanguage), icon: "gear") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            
            MenuBarButton(title: "Quit".localized(language: selectedLanguage), icon: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 280)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleSettingsWindow"))) { _ in
             NSApp.activate(ignoringOtherApps: true)
             openWindow(id: "settings")
        }
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

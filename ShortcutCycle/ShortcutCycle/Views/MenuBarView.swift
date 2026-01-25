import SwiftUI

/// Menu bar popover view showing quick access to groups
struct MenuBarView: View {
    @EnvironmentObject var store: GroupStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("showDockIcon") private var showDockIcon = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("ShortcutCycle")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Groups list
            if store.groups.isEmpty {
                Text("No groups created yet")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(store.groups) { group in
                    MenuBarGroupRow(group: group)
                }
            }
            
            Divider()
            
            // Preferences
            Toggle("Show Icon in Dock", isOn: $showDockIcon)
                .toggleStyle(.switch)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            Divider()
            
            // Settings button
            MenuBarButton(title: "Settings...", icon: "gear") {
                openWindow(id: "settings")
            }
            
            MenuBarButton(title: "Quit", icon: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 280)
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
            HStack {
                Label(title, systemImage: icon)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        HStack {
            // Enable/Disable Toggle
            Toggle("", isOn: Binding(
                get: { group.isEnabled },
                set: { _ in store.toggleGroupEnabled(group) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            
            Image(systemName: "folder.fill")
                .foregroundColor(group.isEnabled ? .accentColor : .gray)
            
            Text(group.name)
                .foregroundColor(group.isEnabled ? .primary : .secondary)
            
            Spacer()
            
            if group.isEnabled, let shortcut = group.shortcut {
                Text(shortcut.displayString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            
            // Show running app count
            let runningCount = countRunningApps(in: group)
            if runningCount > 0 {
                Circle()
                    .fill(group.isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
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

#Preview {
    MenuBarView()
        .environmentObject(GroupStore())
}

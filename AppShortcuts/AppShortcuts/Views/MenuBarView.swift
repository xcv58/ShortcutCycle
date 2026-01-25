import SwiftUI

/// Menu bar popover view showing quick access to groups
struct MenuBarView: View {
    @EnvironmentObject var store: GroupStore
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("App Shortcuts")
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
            
            // Settings button
            Button(action: {
                openWindow(id: "settings")
            }) {
                Label("Settings...", systemImage: "gear")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }
}

/// A single group row in the menu bar view
struct MenuBarGroupRow: View {
    let group: AppGroup
    
    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)
            
            Text(group.name)
            
            Spacer()
            
            if let shortcut = group.shortcut {
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
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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

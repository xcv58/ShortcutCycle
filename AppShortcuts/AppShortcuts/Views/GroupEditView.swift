import SwiftUI

/// View for editing a single app group
struct GroupEditView: View {
    @EnvironmentObject var store: GroupStore
    let groupId: UUID
    
    @State private var groupName: String = ""
    @State private var shortcut: KeyboardShortcutData?
    
    private var group: AppGroup? {
        store.groups.first { $0.id == groupId }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let group = group {
                // Group Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group Name")
                        .font(.headline)
                    
                    TextField("Enter group name", text: $groupName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: groupName) { _, newValue in
                            var updatedGroup = group
                            updatedGroup.name = newValue
                            store.updateGroup(updatedGroup)
                        }
                }
                
                Divider()
                
                // Shortcut
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keyboard Shortcut")
                        .font(.headline)
                    
                    ShortcutRecorderView(shortcut: $shortcut)
                        .onChange(of: shortcut) { _, newValue in
                            store.setShortcut(newValue, for: groupId)
                            ShortcutManager.shared.registerAllShortcuts()
                        }
                }
                
                Divider()
                
                // Apps List
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Applications")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(group.apps.count) apps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if group.apps.isEmpty {
                        Text("No apps added yet. Drag apps here from Finder.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        List {
                            ForEach(group.apps) { app in
                                AppRowView(app: app) {
                                    store.removeApp(app, from: groupId)
                                }
                            }
                            .onMove { indices, newOffset in
                                store.moveApp(in: groupId, from: indices, to: newOffset)
                            }
                        }
                        .listStyle(.plain)
                        .frame(minHeight: 150)
                    }
                    
                    // Drop zone for adding apps
                    AppDropZoneView(apps: .constant(group.apps)) { app in
                        store.addApp(app, to: groupId)
                    }
                }
                
                Spacer()
            } else {
                Text("Select a group to edit")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .onAppear {
            loadGroupData()
        }
        .onChange(of: groupId) { _, _ in
            loadGroupData()
        }
    }
    
    private func loadGroupData() {
        if let group = group {
            groupName = group.name
            shortcut = group.shortcut
        }
    }
}

#Preview {
    let store = GroupStore()
    
    return GroupEditView(groupId: store.groups.first?.id ?? UUID())
        .environmentObject(store)
        .frame(width: 400, height: 500)
}

import SwiftUI

/// Sidebar view showing the list of all groups
struct GroupListView: View {
    @EnvironmentObject var store: GroupStore
    @State private var isAddingGroup = false
    @State private var newGroupName = ""
    @State private var groupToRename: AppGroup?
    @State private var renameText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Groups list
            List(selection: $store.selectedGroupId) {
                ForEach(store.groups) { group in
                    GroupRowView(group: group)
                        .tag(group.id)
                        .contextMenu {
                            Button("Rename") {
                                groupToRename = group
                                renameText = group.name
                            }
                            
                            Button("Delete", role: .destructive) {
                                store.deleteGroup(group)
                                ShortcutManager.shared.registerAllShortcuts()
                            }
                        }
                }
                .onMove { indices, newOffset in
                    store.moveGroups(from: indices, to: newOffset)
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            // Add group button
            if isAddingGroup {
                HStack {
                    TextField("Group name", text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addGroup()
                        }
                    
                    Button(action: addGroup) {
                        Image(systemName: "checkmark")
                    }
                    .disabled(newGroupName.isEmpty)
                    
                    Button(action: cancelAdd) {
                        Image(systemName: "xmark")
                    }
                }
                .padding(8)
            } else {
                Button(action: { isAddingGroup = true }) {
                    Label("Add Group", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .alert("Rename Group", isPresented: Binding(
            get: { groupToRename != nil },
            set: { if !$0 { groupToRename = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let group = groupToRename, !renameText.isEmpty {
                    store.renameGroup(group, newName: renameText)
                }
                groupToRename = nil
            }
            Button("Cancel", role: .cancel) {
                groupToRename = nil
            }
        }
    }
    
    private func addGroup() {
        guard !newGroupName.isEmpty else { return }
        _ = store.addGroup(name: newGroupName)
        newGroupName = ""
        isAddingGroup = false
    }
    
    private func cancelAdd() {
        newGroupName = ""
        isAddingGroup = false
    }
}

/// A single row in the groups list
struct GroupRowView: View {
    let group: AppGroup
    
    var body: some View {
        HStack(spacing: 8) {
            // Group icon
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .fontWeight(.medium)
                
                if let shortcut = group.shortcut {
                    Text(shortcut.displayString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                } else {
                    Text("No shortcut")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // App count badge
            Text("\(group.apps.count)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.gray.opacity(0.5)))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    GroupListView()
        .environmentObject(GroupStore())
        .frame(width: 250, height: 400)
}

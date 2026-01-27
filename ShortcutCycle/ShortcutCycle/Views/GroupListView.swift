import SwiftUI
import KeyboardShortcuts

/// Sidebar view showing the list of all groups
struct GroupListView: View {
    @EnvironmentObject var store: GroupStore
    @State private var isAddingGroup = false
    @State private var newGroupName = ""
    @State private var groupToRename: AppGroup?
    @State private var renameText = ""
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    
    var body: some View {
        VStack(spacing: 0) {
            // Groups list
            List(selection: $store.selectedGroupId) {
                ForEach(store.groups) { group in
                    GroupRowView(group: group)
                        .tag(group.id)
                        .contextMenu {
                            Button("Rename".localized(language: selectedLanguage)) {
                                groupToRename = group
                                renameText = group.name
                            }
                            
                            Button("Delete".localized(language: selectedLanguage), role: .destructive) {
                                store.deleteGroup(group)
                            }
                        }
                }
                .onMove { indices, newOffset in
                    store.moveGroups(from: indices, to: newOffset)
                }
            }
            .listStyle(.sidebar)
            .id(selectedLanguage) // Force redraw of list and context menus when language changes
            
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

            Button("Cancel".localized(language: selectedLanguage), role: .cancel) {
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
    @EnvironmentObject var store: GroupStore
    @State private var showDeleteConfirmation = false
    @State private var isHovering = false
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    
    var body: some View {
        HStack(spacing: 6) {
            // Enable/Disable toggle
            Toggle("", isOn: Binding(
                get: { group.isEnabled },
                set: { _ in
                    store.toggleGroupEnabled(group)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(group.isEnabled ? "Disable group".localized(language: selectedLanguage) : "Enable group".localized(language: selectedLanguage))
            
            // Group icon
            Image(systemName: "folder.fill")
                .foregroundColor(group.isEnabled ? .accentColor : .gray)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .fontWeight(.medium)
                    .foregroundColor(group.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                if let shortcutString = group.shortcutDisplayString {
                    Text(shortcutString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                        .lineLimit(1)
                } else {
                    Text("No shortcut".localized(language: selectedLanguage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1) // Prioritize text visibility
            
            Spacer(minLength: 0)
            
            // App count badge
            Text("\(group.apps.count)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.gray.opacity(0.5)))
                .layoutPriority(1)
            
            // Delete button (Visible only on hover)
            if isHovering {
                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete group".localized(language: selectedLanguage))
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .opacity(group.isEnabled ? 1.0 : 0.6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .confirmationDialog("Delete '\(group.name)'?", isPresented: $showDeleteConfirmation) {
            Button("Delete".localized(language: selectedLanguage), role: .destructive) {
                store.deleteGroup(group)
            }
            Button("Cancel".localized(language: selectedLanguage), role: .cancel) {}
        } message: {
            Text("This action cannot be undone.".localized(language: selectedLanguage))
        }
    }
}

#Preview {
    GroupListView()
        .environmentObject(GroupStore.shared)
        .frame(width: 250, height: 400)
}

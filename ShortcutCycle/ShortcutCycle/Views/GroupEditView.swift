import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif
import UniformTypeIdentifiers
import KeyboardShortcuts

/// View for editing a single app group
struct GroupEditView: View {
    @EnvironmentObject var store: GroupStore
    let groupId: UUID
    
    @State private var groupName: String = ""
    @State private var draggingApp: AppItem?
    
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
                        .onChange(of: groupName) { newValue in
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
                    
                    HStack {
                        KeyboardShortcuts.Recorder(for: .forGroup(groupId))
                            .onChange(of: KeyboardShortcuts.getShortcut(for: .forGroup(groupId))) { _ in
                                // Re-register shortcuts when changed
                                ShortcutManager.shared.registerAllShortcuts()
                            }
                    }
                    
                    Toggle("Cycle through all apps (open if needed)", isOn: Binding(
                        get: { group.shouldOpenAppIfNeeded },
                        set: { newValue in
                            var updatedGroup = group
                            updatedGroup.openAppIfNeeded = newValue
                            store.updateGroup(updatedGroup)
                        }
                    ))
                    .font(.caption)
                    .padding(.top, 4)
                }
                
                Divider()
                
                // Apps Grid
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Applications")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(group.apps.count) \(group.apps.count == 1 ? "app" : "apps")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if group.apps.isEmpty {
                        Text("No apps added yet. Drag apps here or click the drop zone below.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 100))], spacing: 16) {
                            ForEach(group.apps) { app in
                                AppGridItemView(app: app) {
                                    store.removeApp(app, from: groupId)
                                }
                                .opacity(draggingApp?.id == app.id ? 0.01 : 1)
                                .onDrag {
                                    draggingApp = app
                                    return NSItemProvider(object: app.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: AppReorderDelegate(
                                    item: app,
                                    draggingApp: $draggingApp,
                                    store: store,
                                    groupId: groupId
                                ))
                            }
                        }
                        .padding(.vertical, 8)
                        .animation(.default, value: group.apps)
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
        .onChange(of: groupId) { _ in
            loadGroupData()
        }
    }
    
    private func loadGroupData() {
        if let group = group {
            groupName = group.name
        }
    }
}

struct AppReorderDelegate: DropDelegate {
    let item: AppItem
    @Binding var draggingApp: AppItem?
    let store: GroupStore
    let groupId: UUID

    func dropEntered(info: DropInfo) {
        guard let draggingApp = draggingApp,
              draggingApp.id != item.id,
              let group = store.groups.first(where: { $0.id == groupId }),
              let fromIndex = group.apps.firstIndex(of: draggingApp),
              let toIndex = group.apps.firstIndex(of: item)
        else { return }
        
        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        store.moveApp(in: groupId, from: IndexSet(integer: fromIndex), to: destination)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggingApp = nil
        return true
    }
}

#Preview {
    let store = GroupStore.shared
    
    return GroupEditView(groupId: store.groups.first?.id ?? UUID())
        .environmentObject(store)
        .frame(width: 400, height: 500)
}

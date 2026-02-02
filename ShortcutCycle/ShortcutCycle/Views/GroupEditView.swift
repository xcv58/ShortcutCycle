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
    
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @State private var groupName: String = ""
    @State private var draggingApp: AppItem?
    @State private var isHovering: Bool = false
    @FocusState private var isNameFocused: Bool
    
    private var group: AppGroup? {
        store.groups.first { $0.id == groupId }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let group = group {
                // Group Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group Name".localized(language: selectedLanguage))
                        .font(.headline)
                    
                    TextField("Untitled Group", text: $groupName)
                        .focused($isNameFocused)
                        .font(.title2)
                        .fontWeight(.medium)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
                        )
                        .onHover { hovering in
                            isHovering = hovering
                        }
                        .onChange(of: groupName) { _, newValue in
                            var updatedGroup = group
                            updatedGroup.name = newValue
                            store.updateGroup(updatedGroup)
                        }
                }
                
                Divider()
                
                // Shortcut
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keyboard Shortcut".localized(language: selectedLanguage))
                        .font(.headline)
                    
                    HStack {
                        KeyboardShortcuts.Recorder(for: .forGroup(groupId))
                        .onChange(of: KeyboardShortcuts.getShortcut(for: .forGroup(groupId))) { _, _ in
                                // Re-register shortcuts when changed
                                ShortcutManager.shared.registerAllShortcuts()
                            }
                    }
                    
                    Picker("Cycling Mode".localized(language: selectedLanguage), selection: Binding(
                        get: { group.shouldOpenAppIfNeeded },
                        set: { newValue in
                            DispatchQueue.main.async {
                                var updatedGroup = group
                                updatedGroup.openAppIfNeeded = newValue
                                store.updateGroup(updatedGroup)
                            }
                        }
                    )) {
                        Text("Running apps only".localized(language: selectedLanguage)).tag(false)
                        Text("All apps (open if needed)".localized(language: selectedLanguage)).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .font(.caption)
                    .padding(.top, 4)

                    Text(group.shouldOpenAppIfNeeded
                        ? "Cycle through all apps in the group. Non-running apps will be launched when selected.".localized(language: selectedLanguage)
                        : "Cycle through running apps only. If no app is running, the first app in the group will be launched.".localized(language: selectedLanguage)
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                }
                
                Divider()
                
                // Apps Grid
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Applications".localized(language: selectedLanguage))
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(group.apps.count) \(group.apps.count == 1 ? "app".localized(language: selectedLanguage) : "apps".localized(language: selectedLanguage))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if group.apps.isEmpty {
                        Text("No apps added yet. Drag apps here or click the drop zone below.".localized(language: selectedLanguage))
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
                Text("Select a group to edit".localized(language: selectedLanguage))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }
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

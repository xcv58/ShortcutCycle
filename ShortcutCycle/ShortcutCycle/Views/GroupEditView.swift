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
    @State private var suppressAutoFocus = true

    private var group: AppGroup? {
        store.groups.first { $0.id == groupId }
    }

    var body: some View {
        ScrollView {
            content
        }
        .padding()
        .onAppear {
            loadGroupData()
            // Prevent the system from auto-focusing the name field on appear
            suppressAutoFocus = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                suppressAutoFocus = false
            }
        }
        .onChange(of: isNameFocused) { _, focused in
            if focused && suppressAutoFocus {
                isNameFocused = false
            }
        }
        .onChange(of: groupId) { _, _ in
            suppressAutoFocus = true
            loadGroupData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                suppressAutoFocus = false
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let group = group {
            VStack(alignment: .leading, spacing: 20) {
                groupNameSection(for: group)

                Divider()

                GroupShortcutEditor(group: group, groupId: groupId)

                Divider()

                appsSection(for: group)

                Spacer()
            }
        } else {
            Text("Select a group to edit".localized(language: selectedLanguage))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func groupNameSection(for group: AppGroup) -> some View {
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
                    guard isNameFocused else { return }
                    var updatedGroup = group
                    updatedGroup.name = newValue
                    store.updateGroup(updatedGroup)
                }
        }
    }

    private func appsSection(for group: AppGroup) -> some View {
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

            AppDropZoneView(apps: .constant(group.apps)) { app in
                store.addApp(app, to: groupId)
            }
        }
    }

    private func loadGroupData() {
        if let group = group {
            groupName = group.name
        }
    }
}

private struct GroupShortcutEditor: View {
    @EnvironmentObject private var store: GroupStore

    let group: AppGroup
    let groupId: UUID

    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @State private var shortcutRefreshToken = 0

    private var shortcutName: KeyboardShortcuts.Name {
        .forGroup(groupId)
    }

    private var currentShortcut: KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: shortcutName)
    }

    private var suggestionShortcuts: [KeyboardShortcuts.Shortcut] {
        ShortcutSuggestions.available(for: store.groups, excluding: groupId)
    }

    private var shouldShowSuggestions: Bool {
        currentShortcut == nil && !suggestionShortcuts.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard Shortcut".localized(language: selectedLanguage))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                KeyboardShortcuts.Recorder(for: shortcutName)
                    .onChange(of: currentShortcut) { _, _ in
                        ShortcutManager.shared.registerAllShortcuts()
                    }

                if shouldShowSuggestions {
                    ShortcutSuggestionRow(
                        suggestions: suggestionShortcuts,
                        onSelect: assignShortcut
                    )
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
    }

    @MainActor
    private func assignShortcut(_ shortcut: KeyboardShortcuts.Shortcut) {
        KeyboardShortcuts.setShortcut(shortcut, for: shortcutName)
        shortcutRefreshToken += 1
        ShortcutManager.shared.registerAllShortcuts()
    }
}

private struct ShortcutSuggestionRow: View {
    let suggestions: [KeyboardShortcuts.Shortcut]
    let onSelect: (KeyboardShortcuts.Shortcut) -> Void

    @AppStorage("selectedLanguage") private var selectedLanguage = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, shortcut in
                    Button {
                        onSelect(shortcut)
                    } label: {
                        Text(shortcut.description)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(shortcut.description)
                }
            }

            Text("Try a simple pattern like ⌥1, ⌥2, and ⌥3.".localized(language: selectedLanguage))
                .font(.caption2)
                .foregroundStyle(.secondary)
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

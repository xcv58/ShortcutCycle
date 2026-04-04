import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif
import AppKit
import UniformTypeIdentifiers
import KeyboardShortcuts

/// View for editing a single app group
struct GroupEditView: View {
    @EnvironmentObject var store: GroupStore
    let groupId: UUID
    private let runningAppCandidatesProvider: ([AppItem]) -> [AppItem]

    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @State private var groupName: String = ""
    @State private var draggingApp: AppItem?
    @State private var isHovering: Bool = false
    @FocusState private var isNameFocused: Bool
    @State private var suppressAutoFocus = true
    @State private var runningAppsRefreshToken = 0

    init(
        groupId: UUID,
        runningAppCandidatesProvider: @escaping ([AppItem]) -> [AppItem] = GroupEditView.defaultRunningAppCandidates(for:)
    ) {
        self.groupId = groupId
        self.runningAppCandidatesProvider = runningAppCandidatesProvider
    }

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
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            runningAppsRefreshToken += 1
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            runningAppsRefreshToken += 1
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
        let quickAddCandidates = runningAppCandidates(for: group)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Applications".localized(language: selectedLanguage))
                    .font(.headline)

                Spacer()

                Text("\(group.apps.count) \(group.apps.count == 1 ? "app".localized(language: selectedLanguage) : "apps".localized(language: selectedLanguage))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if group.apps.isEmpty {
                Text("No apps in this group yet.".localized(language: selectedLanguage))
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

            addAppsPanel(for: group, quickAddCandidates: quickAddCandidates)
        }
    }

    private func addAppsPanel(for group: AppGroup, quickAddCandidates: [AppItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Apps".localized(language: selectedLanguage))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            if Self.shouldShowRunningAppQuickAddSection(quickAddCandidates) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        runningAppsOptionCard(quickAddCandidates)
                            .frame(minWidth: 360, maxWidth: .infinity, alignment: .leading)

                        Divider()
                            .padding(.vertical, 4)

                        browseAppsOptionCard(for: group)
                            .frame(minWidth: 220, idealWidth: 240, maxWidth: 280, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        runningAppsOptionCard(quickAddCandidates)
                        browseAppsOptionCard(for: group)
                    }
                }
            } else {
                browseAppsOptionCard(for: group)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    private func runningAppsOptionCard(_ quickAddCandidates: [AppItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Running Apps".localized(language: selectedLanguage))
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)

            Text("Click to add currently open apps to this group.".localized(language: selectedLanguage))
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78, maximum: 90))], spacing: 10) {
                ForEach(quickAddCandidates) { app in
                    RunningAppQuickAddButton(app: app) {
                        store.addApp(app, to: groupId)
                    }
                }
            }
        }
    }

    private func browseAppsOptionCard(for group: AppGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse or drag from Finder".localized(language: selectedLanguage))
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)

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

    private func runningAppCandidates(for group: AppGroup) -> [AppItem] {
        _ = runningAppsRefreshToken
        return runningAppCandidatesProvider(group.apps)
    }

    private static func defaultRunningAppCandidates(for groupApps: [AppItem]) -> [AppItem] {
        let runningApps: [RunningAppQuickAddSource] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleIdentifier = app.bundleIdentifier else { return nil }
            return RunningAppQuickAddSource(
                bundleIdentifier: bundleIdentifier,
                bundleURL: app.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
                isRegularApp: app.activationPolicy == .regular
            )
        }
        let excludedBundleIdentifiers = Set(["com.xcv58.ShortcutCycle", Bundle.main.bundleIdentifier].compactMap { $0 })
        return RunningAppQuickAdd.candidates(
            for: groupApps,
            runningApps: runningApps,
            excludedBundleIdentifiers: excludedBundleIdentifiers
        )
    }

    static func shouldShowRunningAppQuickAddSection(_ quickAddCandidates: [AppItem]) -> Bool {
        !quickAddCandidates.isEmpty
    }
}

private struct RunningAppQuickAddButton: View {
    let app: AppItem
    let onAdd: () -> Void

    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @State private var isHovered = false

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                .resizable()
                                .frame(width: 30, height: 30)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                                .frame(width: 30, height: 30)
                        }
                    }

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                        .offset(x: 4, y: -4)
                }

                Text(app.name)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.accentColor.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel("\("Add".localized(language: selectedLanguage)) \(app.name)")
        .help(app.name)
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

    private var cyclingModeSelection: Binding<Bool> {
        Binding(
            get: { group.shouldOpenAppIfNeeded },
            set: { newValue in
                DispatchQueue.main.async {
                    var updatedGroup = group
                    updatedGroup.openAppIfNeeded = newValue
                    store.updateGroup(updatedGroup)
                }
            }
        )
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
                KeyboardShortcuts.Recorder(for: shortcutName, onChange: handleShortcutChange)
                    .padding(.leading, 4)

                if shouldShowSuggestions {
                    ShortcutSuggestionRow(
                        suggestions: suggestionShortcuts,
                        onSelect: assignShortcut
                    )
                }
            }

            Divider()

            HStack {
                Text("Cycling Mode".localized(language: selectedLanguage))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                ViewThatFits(in: .horizontal) {
                    Picker("Cycling Mode".localized(language: selectedLanguage), selection: cyclingModeSelection) {
                        Text("Running apps only".localized(language: selectedLanguage)).tag(false)
                        Text("All apps (open if needed)".localized(language: selectedLanguage)).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .font(.caption)
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)

                    Picker("Cycling Mode".localized(language: selectedLanguage), selection: cyclingModeSelection) {
                        Text("Running apps only".localized(language: selectedLanguage)).tag(false)
                        Text("All apps (open if needed)".localized(language: selectedLanguage)).tag(true)
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                    .labelsHidden()
                }
            }

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
        refreshShortcutState()
    }

    @MainActor
    private func handleShortcutChange(_ shortcut: KeyboardShortcuts.Shortcut?) {
        refreshShortcutState()
    }

    @MainActor
    private func refreshShortcutState() {
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

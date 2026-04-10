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
    @Environment(\.colorScheme) private var colorScheme
    let groupId: UUID
    private let runningAppCandidatesProvider: ([AppItem]) -> [AppItem]

    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @State private var groupName: String = ""
    @State private var draggingApp: AppItem?
    @State private var dragPreviewApps: [AppItem]?
    @State private var isNameFieldHovered: Bool = false
    @FocusState private var isNameFocused: Bool
    @State private var suppressAutoFocus = true
    @State private var quickAddCandidates: [AppItem] = []

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
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsChromePalette.windowBackground(for: colorScheme))
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
        .onChange(of: (group?.apps.map(\.bundleIdentifier).sorted()) ?? []) { _, _ in
            dragPreviewApps = nil
            refreshQuickAddCandidates()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshQuickAddCandidates()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshQuickAddCandidates()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let group = group {
            VStack(alignment: .leading, spacing: 20) {
                groupNameSection(for: group)

                SettingsSectionDivider()

                GroupShortcutEditor(group: group, groupId: groupId)

                SettingsSectionDivider()

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
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(nameFieldBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(nameFieldBorderColor, lineWidth: nameFieldBorderWidth)
                )
                .shadow(
                    color: nameFieldGlowColor,
                    radius: nameFieldGlowRadius,
                    x: 0,
                    y: 0
                )
                .animation(.easeInOut(duration: 0.15), value: isNameFocused)
                .animation(.easeInOut(duration: 0.15), value: isNameFieldHovered)
                .onHover { hovering in
                    isNameFieldHovered = hovering
                }
                .onChange(of: groupName) { _, newValue in
                    guard isNameFocused else { return }
                    var updatedGroup = group
                    updatedGroup.name = newValue
                    store.updateGroup(updatedGroup)
                }
        }
    }

    private var nameFieldBackgroundColor: Color {
        if isNameFocused {
            return SettingsChromePalette.focusRingFill(for: colorScheme)
        }

        if isNameFieldHovered {
            return SettingsChromePalette.hoverRingFill(for: colorScheme)
        }

        return .clear
    }

    private var nameFieldBorderColor: Color {
        if isNameFocused {
            return SettingsChromePalette.focusRingBorder(for: colorScheme)
        }

        if isNameFieldHovered {
            return SettingsChromePalette.hoverRingBorder(for: colorScheme)
        }

        return .clear
    }

    private var nameFieldBorderWidth: CGFloat {
        isNameFocused ? 1.5 : (isNameFieldHovered ? 1 : 0)
    }

    private var nameFieldGlowColor: Color {
        if isNameFocused {
            return SettingsChromePalette.focusRingGlow(for: colorScheme)
        }

        if isNameFieldHovered {
            return SettingsChromePalette.hoverRingGlow(for: colorScheme)
        }

        return .clear
    }

    private var nameFieldGlowRadius: CGFloat {
        if isNameFocused {
            return 8
        }

        return isNameFieldHovered ? 4 : 0
    }

    private func appsSection(for group: AppGroup) -> some View {
        let displayedApps = dragPreviewApps ?? group.apps

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
                    ForEach(displayedApps) { app in
                        AppGridItemView(
                            app: app,
                            isPlaceholder: draggingApp?.id == app.id
                        ) {
                            store.removeApp(app, from: groupId)
                        }
                        .onDrag {
                            draggingApp = app
                            return NSItemProvider(object: app.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: AppReorderDelegate(
                            item: app,
                            draggingApp: $draggingApp,
                            dragPreviewApps: $dragPreviewApps,
                            store: store,
                            groupId: groupId
                        ))
                    }
                }
                .padding(.vertical, 8)
                // Only animate the temporary drag preview; switching groups should update immediately.
                .animation(.default, value: dragPreviewApps?.map(\.id) ?? [])
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

                        if colorScheme == .dark {
                            Rectangle()
                                .fill(SettingsChromePalette.panelBorder(for: colorScheme))
                                .frame(width: 1)
                                .padding(.vertical, 4)
                        } else {
                            Divider()
                                .padding(.vertical, 4)
                        }

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
                .fill(SettingsChromePalette.panelBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(SettingsChromePalette.panelBorder(for: colorScheme), lineWidth: 1)
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
        dragPreviewApps = nil
        refreshQuickAddCandidates()
    }

    private func refreshQuickAddCandidates() {
        guard let group else {
            quickAddCandidates = []
            return
        }

        quickAddCandidates = runningAppCandidatesProvider(group.apps)
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AppIconThumbnailView(app: app, size: 30, fallbackFontSize: 24)

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
                    .fill(isHovered ? SettingsChromePalette.neutralHoverFill(for: colorScheme) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? SettingsChromePalette.neutralHoverBorder(for: colorScheme) : Color.clear, lineWidth: 1)
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
                    .id("\(selectedLanguage)-\(groupId.uuidString)") // Recreate only when localization or target group changes

                if shouldShowSuggestions {
                    ShortcutSuggestionRow(
                        suggestions: suggestionShortcuts,
                        onSelect: assignShortcut
                    )
                }
            }

            SettingsSectionDivider()

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
    @Binding var dragPreviewApps: [AppItem]?
    let store: GroupStore
    let groupId: UUID

    func dropEntered(info: DropInfo) {
        updatePreviewOrder()
    }

    func updatePreviewOrder() {
        guard let draggingApp,
              draggingApp.id != item.id
        else { return }

        let currentApps = dragPreviewApps ?? store.groups.first(where: { $0.id == groupId })?.apps ?? []
        guard let fromIndex = currentApps.firstIndex(of: draggingApp),
              let toIndex = currentApps.firstIndex(of: item)
        else { return }

        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        var updatedApps = currentApps
        updatedApps.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: destination)

        guard updatedApps != currentApps else { return }
        dragPreviewApps = updatedApps
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        commitPreviewOrder()
        return true
    }

    func commitPreviewOrder() {
        defer {
            draggingApp = nil
            dragPreviewApps = nil
        }

        guard let previewApps = dragPreviewApps else { return }
        store.replaceApps(in: groupId, with: previewApps)
    }
}

#Preview {
    let store = GroupStore.shared

    return GroupEditView(groupId: store.groups.first?.id ?? UUID())
        .environmentObject(store)
        .frame(width: 400, height: 500)
}

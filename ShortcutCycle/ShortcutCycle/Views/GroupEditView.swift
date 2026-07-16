import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif
import AppKit
import UniformTypeIdentifiers
import KeyboardShortcuts

enum AppAccessibilityMoveDirection {
    case earlier
    case later
}

enum AppAccessibilityReorder {
    static func destination(
        for sourceIndex: Int,
        direction: AppAccessibilityMoveDirection,
        count: Int
    ) -> Int? {
        guard sourceIndex >= 0, sourceIndex < count else { return nil }

        switch direction {
        case .earlier:
            return sourceIndex > 0 ? sourceIndex - 1 : nil
        case .later:
            return sourceIndex < count - 1 ? sourceIndex + 2 : nil
        }
    }
}

/// View for editing a single app group
struct GroupEditView: View {
    @EnvironmentObject var store: GroupStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let groupId: UUID
    private let runningAppCandidatesProvider: ([AppItem]) -> [AppItem]

    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @State private var groupName: String = ""
    @State private var draggingApp: AppItem?
    @State private var dragPreviewApps: [AppItem]?
    @State private var isNameFieldHovered: Bool = false
    @FocusState private var isNameFocused: Bool
    @State private var suppressAutoFocus = true
    @State private var areSecondarySectionsMounted = false
    @State private var quickAddCandidates: [AppItem] = []
    @State private var isRefreshingQuickAddCandidates = false
    @State private var secondarySectionsMountTask: Task<Void, Never>?
    @State private var quickAddRefreshTask: Task<Void, Never>?

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
            if areSecondarySectionsMounted {
                scheduleQuickAddCandidatesRefresh()
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            RunningAppQuickAddCatalog.shared.refresh()
            if areSecondarySectionsMounted {
                scheduleQuickAddCandidatesRefresh()
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            RunningAppQuickAddCatalog.shared.refresh()
            if areSecondarySectionsMounted {
                scheduleQuickAddCandidatesRefresh()
            }
        }
        .onDisappear {
            secondarySectionsMountTask?.cancel()
            quickAddRefreshTask?.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let group = group {
            VStack(alignment: .leading, spacing: 20) {
                groupNameSection(for: group)

                SettingsSectionDivider()

                GroupShortcutEditor(
                    group: group,
                    groupId: groupId
                )

                SettingsSectionDivider()

                if areSecondarySectionsMounted {
                    appsSection(for: group)
                } else {
                    secondarySectionsPlaceholder
                }

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
        .task(id: groupId) {
            GroupSwitchPerformanceTracker.shared.markHeaderVisible(for: groupId)
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
                    ForEach(Array(displayedApps.enumerated()), id: \.element.id) { index, app in
                        AppGridItemView(
                            app: app,
                            isPlaceholder: draggingApp?.id == app.id,
                            canMoveEarlier: index > 0,
                            canMoveLater: index < displayedApps.count - 1,
                            onDelete: {
                                store.removeApp(app, from: groupId)
                            },
                            onMoveEarlier: {
                                moveApp(app, direction: .earlier)
                            },
                            onMoveLater: {
                                moveApp(app, direction: .later)
                            },
                            onIconResolved: {
                                GroupSwitchPerformanceTracker.shared.markGroupIconResolved(itemId: app.id, for: groupId)
                            }
                        )
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
                .animation(reduceMotion ? nil : .default, value: dragPreviewApps?.map(\.id) ?? [])
            }

            addAppsPanel(
                for: group,
                quickAddCandidates: quickAddCandidates,
                isRefreshingQuickAddCandidates: isRefreshingQuickAddCandidates
            )
        }
        .task(id: groupId) {
            GroupSwitchPerformanceTracker.shared.markAppsSectionVisible(for: groupId)
        }
    }

    private func moveApp(_ app: AppItem, direction: AppAccessibilityMoveDirection) {
        guard let group = store.groups.first(where: { $0.id == groupId }),
              let sourceIndex = group.apps.firstIndex(of: app),
              let destination = AppAccessibilityReorder.destination(
                for: sourceIndex,
                direction: direction,
                count: group.apps.count
              )
        else { return }

        store.moveApp(
            in: groupId,
            from: IndexSet(integer: sourceIndex),
            to: destination
        )
    }

    private var secondarySectionsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Applications".localized(language: selectedLanguage))
                .font(.headline)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SettingsChromePalette.panelBackground(for: colorScheme))
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(SettingsChromePalette.panelBorder(for: colorScheme), lineWidth: 1)
                )
                .overlay {
                    ProgressView()
                        .controlSize(.small)
                }
        }
        .accessibilityHidden(true)
    }

    private func addAppsPanel(
        for group: AppGroup,
        quickAddCandidates: [AppItem],
        isRefreshingQuickAddCandidates: Bool
    ) -> some View {
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
            } else if isRefreshingQuickAddCandidates {
                VStack(alignment: .leading, spacing: 12) {
                    runningAppsLoadingCard()
                    browseAppsOptionCard(for: group)
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

    private func runningAppsLoadingCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Running Apps".localized(language: selectedLanguage))
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)

            ProgressView()
                .controlSize(.small)
                .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        scheduleSecondarySectionsMount()

        if let group = group {
            groupName = group.name
            IconCache.shared.prefetchIcons(for: group.apps)
        }
        dragPreviewApps = nil
        quickAddRefreshTask?.cancel()
        quickAddCandidates = []
        isRefreshingQuickAddCandidates = false
    }

    private func scheduleSecondarySectionsMount() {
        secondarySectionsMountTask?.cancel()
        areSecondarySectionsMounted = false

        guard group != nil else { return }

        secondarySectionsMountTask = Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled else { return }
            areSecondarySectionsMounted = true
            scheduleQuickAddCandidatesRefresh()
        }
    }

    private func scheduleQuickAddCandidatesRefresh() {
        quickAddRefreshTask?.cancel()

        guard let group else {
            quickAddCandidates = []
            isRefreshingQuickAddCandidates = false
            return
        }

        let groupApps = group.apps
        quickAddCandidates = []
        isRefreshingQuickAddCandidates = true
        GroupSwitchPerformanceTracker.shared.markQuickAddRefreshStarted(for: groupId)

        quickAddRefreshTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }

            let candidates = runningAppCandidatesProvider(groupApps)
            guard !Task.isCancelled else { return }

            quickAddCandidates = candidates
            isRefreshingQuickAddCandidates = false
            IconCache.shared.prefetchIcons(for: candidates)
            GroupSwitchPerformanceTracker.shared.markQuickAddReady(for: groupId, candidateCount: candidates.count)
        }
    }

    private static func defaultRunningAppCandidates(for groupApps: [AppItem]) -> [AppItem] {
        RunningAppQuickAddCatalog.shared.candidates(for: groupApps)
    }

    static func shouldShowRunningAppQuickAddSection(_ quickAddCandidates: [AppItem]) -> Bool {
        !quickAddCandidates.isEmpty
    }
}

@MainActor
final class RunningAppQuickAddCatalog {
    static let shared = RunningAppQuickAddCatalog()

    private var cachedApps: [AppItem] = []
    private var hasLoaded = false
    #if DEBUG
    private var overrideApps: [AppItem]?
    #endif

    private init() {}

    #if DEBUG
    func setOverrideApps(_ apps: [AppItem]?) {
        overrideApps = apps
        cachedApps = apps ?? []
        hasLoaded = apps != nil
    }
    #endif

    func refresh() {
        #if DEBUG
        if let overrideApps {
            cachedApps = overrideApps
            hasLoaded = true
            return
        }
        #endif

        let excludedBundleIdentifiers = Set(["com.xcv58.ShortcutCycle", Bundle.main.bundleIdentifier].compactMap { $0 })
        var seenBundleIdentifiers = Set<String>()

        cachedApps = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular else { return nil }
            guard let bundleIdentifier = app.bundleIdentifier else { return nil }
            guard !excludedBundleIdentifiers.contains(bundleIdentifier) else { return nil }
            guard seenBundleIdentifiers.insert(bundleIdentifier).inserted else { return nil }
            guard let appURL = app.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                return nil
            }
            return AppItem.from(appURL: appURL)
        }
        .sorted { lhs, rhs in
            let lhsKey = lhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let rhsKey = rhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

            if lhsKey == rhsKey {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }

            return lhsKey < rhsKey
        }

        hasLoaded = true
    }

    func candidates(for groupApps: [AppItem]) -> [AppItem] {
        if !hasLoaded {
            refresh()
        }

        let excludedBundleIdentifiers = Set(groupApps.map(\.bundleIdentifier))
        return cachedApps.filter { !excludedBundleIdentifiers.contains($0.bundleIdentifier) }
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
                    AppIconThumbnailView(app: app, size: 30, fallbackFontSize: 24, onIconResolved: nil)

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
    @State private var shortcutConflict: ShortcutAssignmentConflict?

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
        ShortcutSuggestions.available(
            for: store.groups,
            excluding: groupId,
            recentShortcuts: group.recentShortcuts?.map(\.shortcut) ?? [],
            currentShortcut: currentShortcut
        )
    }

    private var shouldShowSuggestions: Bool {
        !suggestionShortcuts.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard Shortcut".localized(language: selectedLanguage))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                LocalizedKeyboardShortcutRecorder(
                    name: shortcutName,
                    selectedLanguage: selectedLanguage,
                    onRecord: recordShortcut,
                    onBeginRecording: suspendGlobalShortcuts,
                    onEndRecording: resumeGlobalShortcuts
                )
                    .padding(.leading, 4)
                    .id("\(selectedLanguage)-\(groupId.uuidString)-\(shortcutRefreshToken)")
                    .task(id: groupId) {
                        GroupSwitchPerformanceTracker.shared.markRecorderMounted(for: groupId)
                    }

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
        .task(id: groupId) {
            GroupSwitchPerformanceTracker.shared.markShortcutSectionVisible(for: groupId)
        }
        .alert(item: $shortcutConflict) { conflict in
            Alert(
                title: Text("Shortcut Already Used".localized(language: selectedLanguage)),
                message: Text(conflict.message { $0.localized(language: selectedLanguage) }),
                dismissButton: .default(Text("OK".localized(language: selectedLanguage)))
            )
        }
    }

    @MainActor
    private func assignShortcut(_ shortcut: KeyboardShortcuts.Shortcut) {
        if let conflict = conflict(for: shortcut) {
            shortcutConflict = conflict
            return
        }

        applyShortcut(shortcut)
    }

    @MainActor
    private func recordShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) -> ShortcutRecorderRecordingResult {
        if let conflict = conflict(for: shortcut) {
            return .rejected(conflict.message { $0.localized(language: selectedLanguage) })
        }

        applyShortcut(shortcut)
        return .accepted
    }

    @MainActor
    private func applyShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        let previousShortcut = currentShortcut
        if previousShortcut != shortcut, let previousShortcut {
            store.rememberShortcut(previousShortcut, for: groupId)
        }

        KeyboardShortcuts.setShortcut(shortcut, for: shortcutName)
        refreshShortcutState()
    }

    @MainActor
    private func suspendGlobalShortcuts() {
        ShortcutManager.shared.suspendForShortcutRecording()
    }

    @MainActor
    private func resumeGlobalShortcuts() {
        ShortcutManager.shared.resumeAfterShortcutRecording()
    }

    @MainActor
    private func conflict(
        for shortcut: KeyboardShortcuts.Shortcut?
    ) -> ShortcutAssignmentConflict? {
        ShortcutAssignmentConflicts.conflict(
            for: shortcut,
            assigning: .group(id: groupId, name: group.name),
            groups: store.groups
        )
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { _, shortcut in
                        let displayText = ShortcutRecorderDisplay.formattedShortcut(shortcut)

                        Button {
                            onSelect(shortcut)
                        } label: {
                            Text(displayText)
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
                        .help(displayText)
                        .accessibilityLabel(displayText)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            Text("Reuse a recent shortcut or try an available suggestion.".localized(language: selectedLanguage))
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

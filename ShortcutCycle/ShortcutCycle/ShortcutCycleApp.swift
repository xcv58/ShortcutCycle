import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif


// MARK: - Focused Value Keys

struct SelectedTabKey: FocusedValueKey {
    typealias Value = Binding<String>
}

extension FocusedValues {
    var selectedTab: Binding<String>? {
        get { self[SelectedTabKey.self] }
        set { self[SelectedTabKey.self] = newValue }
    }
}

extension Notification.Name {
    static let deleteGroupRequested = Notification.Name("deleteGroupRequested")
    static let settingsTabRequested = Notification.Name("settingsTabRequested")
    static let backupBrowserRequested = Notification.Name("backupBrowserRequested")
}

@MainActor
enum SettingsWindowBridge {
    private static var openWindowAction: OpenWindowAction?

    static func register(openWindow: OpenWindowAction) {
        openWindowAction = openWindow
    }

    static func openSettingsWindow() -> Bool {
        guard let openWindowAction else { return false }
        openWindowAction(id: "settings")
        return true
    }
}


// MARK: - App Commands

struct AppCommands: Commands {
    @FocusedBinding(\.selectedTab) private var selectedTab
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    private var groupsDisabled: Bool {
        selectedTab != "groups" || GroupStore.shared.groups.count < 2
    }

    private var selectedGroupIndex: Int? {
        guard let currentId = GroupStore.shared.selectedGroupId else { return nil }
        return GroupStore.shared.groups.firstIndex(where: { $0.id == currentId })
    }

    private var canMoveGroupUp: Bool {
        selectedTab == "groups" && (selectedGroupIndex ?? 0) > 0
    }

    private var canMoveGroupDown: Bool {
        guard let selectedGroupIndex else { return false }
        return selectedTab == "groups" && selectedGroupIndex < GroupStore.shared.groups.count - 1
    }

    var body: some Commands {
        // Keep a non-lazy reference to openWindow for URL/shortcut cold-start requests.
        let _ = SettingsWindowBridge.register(openWindow: openWindow)

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                ShortcutCycleURLRouter.openSettingsFromOutsideView(tab: .general)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button("Add Group") {
                selectedTab = "groups"
                GroupStore.shared.columnVisibility = .all
                GroupStore.shared.isAddingGroup = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(selectedTab == nil)

            Button("Delete Group") {
                NotificationCenter.default.post(name: .deleteGroupRequested, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selectedTab != "groups" || GroupStore.shared.selectedGroupId == nil)
        }

        CommandMenu("View") {
            Button("Toggle Sidebar") {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(selectedTab != "groups")

            Button("Toggle Appearance") {
                appTheme = appTheme.toggledAppearance(
                    using: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
                )
            }
            .keyboardShortcut("a", modifiers: [.command, .control])

            Divider()

            Button("Groups") {
                selectedTab = "groups"
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(selectedTab == nil)

            Button("General") {
                selectedTab = "general"
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(selectedTab == nil)

            Divider()

            // Primary: arrow keys
            Button("Previous Group") {
                selectPreviousGroup()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(groupsDisabled)

            Button("Next Group") {
                selectNextGroup()
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(groupsDisabled)

            Divider()

            // Alternative: brackets
            Button("Previous Group") {
                selectPreviousGroup()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(groupsDisabled)

            Button("Next Group") {
                selectNextGroup()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(groupsDisabled)

            // Alternative: vim-style
            Button("Previous Group") {
                selectPreviousGroup()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(groupsDisabled)

            Button("Next Group") {
                selectNextGroup()
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(groupsDisabled)

            Divider()

            Button("Move Group Up") {
                moveSelectedGroup(by: -1)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(!canMoveGroupUp)

            Button("Move Group Down") {
                moveSelectedGroup(by: 1)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(!canMoveGroupDown)
        }
    }

    private func selectPreviousGroup() {
        let store = GroupStore.shared
        guard store.groups.count >= 2 else { return }
        guard let currentId = store.selectedGroupId,
              let currentIndex = store.groups.firstIndex(where: { $0.id == currentId }) else {
            if let firstGroup = store.groups.first {
                GroupSwitchPerformanceTracker.shared.beginGroupSwitch(
                    to: firstGroup.id,
                    source: "command-previous",
                    expectedGroupIconCount: firstGroup.apps.count
                )
                store.selectedGroupId = firstGroup.id
            }
            return
        }
        let previousIndex = currentIndex == 0 ? store.groups.count - 1 : currentIndex - 1
        let previousGroup = store.groups[previousIndex]
        GroupSwitchPerformanceTracker.shared.beginGroupSwitch(
            to: previousGroup.id,
            source: "command-previous",
            expectedGroupIconCount: previousGroup.apps.count
        )
        store.selectedGroupId = previousGroup.id
    }

    private func selectNextGroup() {
        let store = GroupStore.shared
        guard store.groups.count >= 2 else { return }
        guard let currentId = store.selectedGroupId,
              let currentIndex = store.groups.firstIndex(where: { $0.id == currentId }) else {
            if let firstGroup = store.groups.first {
                GroupSwitchPerformanceTracker.shared.beginGroupSwitch(
                    to: firstGroup.id,
                    source: "command-next",
                    expectedGroupIconCount: firstGroup.apps.count
                )
                store.selectedGroupId = firstGroup.id
            }
            return
        }
        let nextIndex = currentIndex == store.groups.count - 1 ? 0 : currentIndex + 1
        let nextGroup = store.groups[nextIndex]
        GroupSwitchPerformanceTracker.shared.beginGroupSwitch(
            to: nextGroup.id,
            source: "command-next",
            expectedGroupIconCount: nextGroup.apps.count
        )
        store.selectedGroupId = nextGroup.id
    }

    private func moveSelectedGroup(by delta: Int) {
        let store = GroupStore.shared
        guard let currentId = store.selectedGroupId,
              let currentIndex = store.groups.firstIndex(where: { $0.id == currentId }) else {
            return
        }

        let targetIndex = currentIndex + delta
        guard store.groups.indices.contains(targetIndex) else { return }

        let destination = delta > 0 ? targetIndex + 1 : targetIndex
        store.moveGroups(from: IndexSet(integer: currentIndex), to: destination)
        store.selectedGroupId = currentId
    }
}


// MARK: - Settings Window Observer

/// Observes the settings window so focus-related affordances can react to key navigation.
struct SettingsWindowObserver: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = ObserverView()
        view.onWindowReady = { window in
            context.coordinator.observe(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ObserverView: NSView {
        var onWindowReady: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onWindowReady?(window)
        }
    }

    final class Coordinator {
        private var keyEventMonitor: Any?
        private weak var observedWindow: NSWindow?

        func observe(window: NSWindow) {
            guard observedWindow !== window else { return }
            removeObservers()
            observedWindow = window

            window.identifier = NSUserInterfaceItemIdentifier("settings")

            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event)
                return event
            }
        }

        func handleKeyDown(_ event: NSEvent) {
            guard shouldRevealFocus(for: event, in: observedWindow) else { return }
            scheduleFocusReveal()
        }

        func shouldRevealFocus(for event: NSEvent, in window: NSWindow?) -> Bool {
            guard let observedWindow, observedWindow === window else {
                return false
            }

            let isObservedWindowEvent = event.window === observedWindow || event.windowNumber == observedWindow.windowNumber
            guard isObservedWindowEvent else { return false }

            return event.keyCode == 48
        }

        func scheduleFocusReveal() {
            DispatchQueue.main.async { [weak self] in
                self?.revealFocusedControl()
                DispatchQueue.main.async { [weak self] in
                    self?.revealFocusedControl()
                }
            }
        }

        func revealFocusedControl() {
            guard let observedWindow,
                  let focusedView = focusedView(in: observedWindow) else {
                return
            }

            focusedView.scrollToVisible(focusedView.bounds.insetBy(dx: 0, dy: -20))
        }

        func focusedView(in window: NSWindow) -> NSView? {
            if let textView = window.firstResponder as? NSTextView {
                if let delegateView = textView.delegate as? NSView {
                    return delegateView
                }

                return textView
            }

            return window.firstResponder as? NSView
        }

        private func removeObservers() {
            if let keyEventMonitor {
                NSEvent.removeMonitor(keyEventMonitor)
                self.keyEventMonitor = nil
            }
        }

        deinit {
            removeObservers()
        }
    }
}

// MARK: - Custom URL Scheme

// MARK: - URL Navigation State

@MainActor
enum ShortcutCycleURLNavigationState {
    private static var pendingSettingsTab: URLSettingsTab?
    private static var pendingOpenBackupBrowser = false

    static func request(tab: URLSettingsTab?) {
        if let tab {
            pendingSettingsTab = tab
        }
    }

    static func requestBackupBrowser() {
        pendingSettingsTab = .general
        pendingOpenBackupBrowser = true
    }

    static func consumePendingSettingsTab() -> URLSettingsTab? {
        defer { pendingSettingsTab = nil }
        return pendingSettingsTab
    }

    static func consumePendingBackupBrowser() -> Bool {
        defer { pendingOpenBackupBrowser = false }
        return pendingOpenBackupBrowser
    }

    static func markSettingsTabHandled(_ tab: URLSettingsTab) {
        if pendingSettingsTab == tab {
            pendingSettingsTab = nil
        }
    }

    static func markBackupBrowserHandled() {
        pendingOpenBackupBrowser = false
    }
}

// MARK: - URL Router

@MainActor
enum ShortcutCycleURLRouter {
    static func openSettingsFromOutsideView(tab: URLSettingsTab? = nil) {
        openSettingsWindow(tab: tab)
    }

    static func handle(_ url: URL) {
        guard let command = ShortcutCycleURLParser.parse(url) else { return }

        let store = GroupStore.shared

        switch command {
        case .openSettings(let tab):
            openSettingsWindow(tab: tab)
        case .openBackupBrowser:
            openBackupBrowser()
        case .cycle(let target):
            guard let group = URLRouterLogic.resolveGroup(target, groups: store.groups, selectedGroup: store.selectedGroup),
                  group.isEnabled else {
                return
            }
            store.selectedGroupId = group.id
            AppSwitcher.shared.handleShortcut(for: group, store: store)
        case .selectGroup(let target):
            guard let group = URLRouterLogic.resolveGroup(target, groups: store.groups, selectedGroup: store.selectedGroup) else { return }
            store.selectedGroupId = group.id
        case .enableGroup(let target):
            setGroupEnabledState(true, for: target, store: store)
        case .disableGroup(let target):
            setGroupEnabledState(false, for: target, store: store)
        case .toggleGroup(let target):
            guard let group = URLRouterLogic.resolveGroup(target, groups: store.groups, selectedGroup: store.selectedGroup) else { return }
            store.toggleGroupEnabled(group)
        case .backup:
            _ = store.manualBackup()
        case .flushAutoSave:
            store.flushPendingSave()
            store.flushPendingBackup()
        case .setSetting(let key, let value):
            applySetting(key: key, value: value)
        case .exportSettings(let path):
            exportSettings(to: path, store: store)
        case .importSettings(let path):
            importSettings(from: path, store: store)
        case .restoreBackup(let target):
            restoreBackup(target: target, store: store)
        case .createGroup(let name):
            _ = store.addGroup(name: name)
            NotificationCenter.default.post(name: .shortcutsNeedUpdate, object: nil)
        case .deleteGroup(let target):
            guard let group = URLRouterLogic.resolveGroup(target, groups: store.groups, selectedGroup: store.selectedGroup) else { return }
            let alert = NSAlert()
            alert.messageText = "Delete '\(group.name)'?"
            alert.informativeText = "This will permanently remove the group and its shortcut."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            store.deleteGroup(group)
        case .renameGroup(let target, let newName):
            guard let group = URLRouterLogic.resolveGroup(target, groups: store.groups, selectedGroup: store.selectedGroup) else { return }
            store.renameGroup(group, newName: newName)
        case .reorderGroup(let target, let position):
            guard let group = URLRouterLogic.resolveGroup(target, groups: store.groups, selectedGroup: store.selectedGroup) else { return }
            guard let currentIndex = store.groups.firstIndex(where: { $0.id == group.id }) else { return }
            let clampedDestination = min(max(position - 1, 0), store.groups.count - 1)
            let toOffset = clampedDestination > currentIndex ? clampedDestination + 1 : clampedDestination
            store.moveGroups(from: IndexSet(integer: currentIndex), to: toOffset)
        case .addApp(let target, let bundleId):
            guard let group = URLRouterLogic.resolveGroup(target, groups: store.groups, selectedGroup: store.selectedGroup) else { return }
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
                  let appItem = AppItem.from(appURL: appURL) else {
                return
            }
            store.addApp(appItem, to: group.id)
        case .removeApp(let target, let bundleId):
            guard let group = URLRouterLogic.resolveGroup(target, groups: store.groups, selectedGroup: store.selectedGroup) else { return }
            guard let appItem = group.apps.first(where: { $0.bundleIdentifier == bundleId }) else { return }
            store.removeApp(appItem, from: group.id)
        case .listGroups:
            let groupsData = store.groups.enumerated().map { index, group in
                [
                    "id": group.id.uuidString,
                    "name": group.name,
                    "isEnabled": group.isEnabled,
                    "appCount": group.apps.count,
                    "index": index + 1
                ] as [String: Any]
            }
            writeQueryResult(groupsData, command: "list-groups")
        case .getGroup(let target):
            guard let group = URLRouterLogic.resolveGroup(target, groups: store.groups, selectedGroup: store.selectedGroup) else {
                writeQueryFailure("Group not found", command: "get-group")
                return
            }
            let appsData = group.apps.map { app in
                [
                    "bundleId": app.bundleIdentifier,
                    "name": app.name
                ]
            }
            let groupData: [String: Any] = [
                "id": group.id.uuidString,
                "name": group.name,
                "isEnabled": group.isEnabled,
                "apps": appsData
            ]
            writeQueryResult(groupData, command: "get-group")
        }
    }

    private static func openSettingsWindow(tab: URLSettingsTab?) {
        if let tab {
            ShortcutCycleURLNavigationState.request(tab: tab)
        }

        if let settingsWindow = NSApp.windows.first(where: { window in
            window.identifier?.rawValue == "settings"
        }) {
            NSApp.setActivationPolicy(.regular)
            if !settingsWindow.isVisible {
                NSApp.unhide(nil)
                settingsWindow.orderFrontRegardless()
            }
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let tab {
                NotificationCenter.default.post(
                    name: .settingsTabRequested,
                    object: tab.rawValue
                )
            }
            return
        }

        requestSettingsWindowOpen()
    }

    private static func openBackupBrowser() {
        ShortcutCycleURLNavigationState.requestBackupBrowser()

        let windowAlreadyOpen = NSApp.windows.contains(where: { window in
            window.identifier?.rawValue == "settings"
        })

        openSettingsWindow(tab: .general)

        if windowAlreadyOpen {
            NotificationCenter.default.post(name: .backupBrowserRequested, object: nil)
        }
    }

    private static func requestSettingsWindowOpen() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if SettingsWindowBridge.openSettingsWindow() {
            return
        }

        let showSettingsSelector = Selector(("showSettingsWindow:"))
        if NSApp.sendAction(showSettingsSelector, to: nil, from: nil) {
            return
        }

        // The app can still be wiring up scenes at launch time. Retry briefly.
        let retryDelays: [TimeInterval] = [0.10, 0.20, 0.40]
        for (index, delay) in retryDelays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard !NSApp.windows.contains(where: { $0.identifier?.rawValue == "settings" }) else { return }

                if SettingsWindowBridge.openSettingsWindow() {
                    return
                }
                _ = NSApp.sendAction(showSettingsSelector, to: nil, from: nil)

                // Keep app visible while retries are in progress.
                if index == retryDelays.count - 1 {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    private static func setGroupEnabledState(_ isEnabled: Bool, for target: URLGroupTarget, store: GroupStore) {
        guard var group = URLRouterLogic.resolveGroup(target, groups: store.groups, selectedGroup: store.selectedGroup) else { return }
        guard group.isEnabled != isEnabled else { return }

        group.isEnabled = isEnabled
        store.updateGroup(group)
        NotificationCenter.default.post(name: .shortcutsNeedUpdate, object: nil)
    }

    private static func applySetting(key: String, value: String) {
        switch key {
        case "showhud", "hud":
            guard let boolValue = URLRouterLogic.parseBool(value) else { return }
            UserDefaults.standard.set(boolValue, forKey: "showHUD")
        case "showshortcutinhud", "hudshortcut", "showshortcut":
            guard let boolValue = URLRouterLogic.parseBool(value) else { return }
            UserDefaults.standard.set(boolValue, forKey: "showShortcutInHUD")
        case "apptheme", "theme", "appearance":
            guard let themeRawValue = URLRouterLogic.parseTheme(value),
                  let theme = AppTheme(rawValue: themeRawValue) else { return }
            UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
        case "selectedlanguage", "language":
            let supportedCodes = LanguageManager.shared.supportedLanguages.map(\.code)
            guard let language = URLRouterLogic.parseLanguage(value, supportedCodes: supportedCodes) else { return }
            UserDefaults.standard.set(language, forKey: "selectedLanguage")
            LanguageManager.shared.syncAppleLanguages(for: language)
        case "openatlogin", "launchatlogin":
            guard let boolValue = URLRouterLogic.parseBool(value) else { return }
            LaunchAtLoginManager.shared.isEnabled = boolValue
        default:
            break
        }
    }

    private static func exportSettings(to rawPath: String?, store: GroupStore) {
        let destinationURL: URL
        if let rawPath {
            switch URLCommandFileValidation.validateImportURL(rawPath: rawPath, home: sandboxHomeURL()) {
            case .success(let explicitURL):
                destinationURL = explicitURL
            case .failure(let error):
                presentURLCommandError(URLRouterLogic.exportPathErrorMessage(for: error, home: NSHomeDirectory()))
                return
            }
        } else {
            destinationURL = defaultExportSettingsFileURL()
        }

        let shouldPromptForOverwrite = rawPath != nil
        if shouldPromptForOverwrite && FileManager.default.fileExists(atPath: destinationURL.path) {
            let alert = NSAlert()
            alert.messageText = "Overwrite Existing File?"
            alert.informativeText = "A file already exists at \(destinationURL.path). Do you want to replace it?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            let data = try store.exportData()
            let parentDirectory = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            presentURLCommandError("Failed to export settings to \(destinationURL.path): \(error.localizedDescription)")
        }
    }

    private static func importSettings(from rawPath: String, store: GroupStore) {
        let fileURL: URL
        switch URLCommandFileValidation.validateImportURL(rawPath: rawPath, home: sandboxHomeURL()) {
        case .success(let validatedURL):
            fileURL = validatedURL
        case .failure(let error):
            presentURLCommandError(URLRouterLogic.importPathErrorMessage(for: error, home: NSHomeDirectory()))
            return
        }

        let alert = NSAlert()
        alert.messageText = "Import Settings?"
        alert.informativeText = "This will replace all current groups and settings with the contents of \(fileURL.lastPathComponent)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            try store.importData(data)
        } catch {
            presentURLCommandError("Failed to import settings from \(fileURL.path): \(error.localizedDescription)")
        }
    }

    private static func restoreBackup(target: URLBackupTarget?, store: GroupStore) {
        let backupURL: URL
        switch URLCommandFileValidation.resolveBackupURL(
            target: target,
            backupDirectory: store.backupDirectory,
            home: sandboxHomeURL()
        ) {
        case .success(let resolvedURL):
            backupURL = resolvedURL
        case .failure(let error):
            presentURLCommandError(URLRouterLogic.backupTargetErrorMessage(for: error, home: NSHomeDirectory()))
            return
        }

        let alert = NSAlert()
        alert.messageText = "Restore Backup?"
        alert.informativeText = "This will replace all current groups and settings with the backup from \(backupURL.lastPathComponent)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let data: Data
        do {
            data = try Data(contentsOf: backupURL)
        } catch {
            presentURLCommandError("Failed to read backup file at \(backupURL.path): \(error.localizedDescription)")
            return
        }

        switch SettingsExport.validate(data: data) {
        case .success(let export):
            store.applyImport(export)
        case .failure(let error):
            presentURLCommandError("Failed to restore backup from \(backupURL.path): \(error.localizedDescription)")
        }
    }

    private static func writeQueryResult(_ data: Any, command: String) {
        let result: [String: Any] = [
            "command": command,
            "success": true,
            "data": data
        ]
        writeQueryPayload(result)
    }

    private static func writeQueryFailure(_ message: String, command: String) {
        let result: [String: Any] = [
            "command": command,
            "success": false,
            "error": message
        ]
        writeQueryPayload(result)
    }

    private static func writeQueryPayload(_ payload: [String: Any]) {
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        } catch {
            print("URL command failed to serialize query payload: \(error.localizedDescription)")
            return
        }

        let url = queryResultFileURL()
        let parentDir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try jsonData.write(to: url, options: .atomic)
        } catch {
            print("URL command failed to write query payload to \(url.path): \(error.localizedDescription)")
        }
    }

    private static func queryResultFileURL() -> URL {
        // In sandboxed builds, NSHomeDirectory() is the app container's Data directory.
        // Writing under <home>/tmp keeps the output deterministic and writable.
        return sandboxHomeURL()
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent(ShortcutCycleURLParser.queryResultFileName, isDirectory: false)
    }

    private static func defaultExportSettingsFileURL() -> URL {
        return sandboxHomeURL()
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("ShortcutCycle-Settings.json", isDirectory: false)
    }

    private static func sandboxHomeURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static func presentURLCommandError(_ message: String) {
        print("URL command failed: \(message)")

        let alert = NSAlert()
        alert.messageText = "URL Command Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }

}


// MARK: - Screenshot Automation

private enum ScreenshotScene: String {
    case general
    case group
    case backups
    case hudHorizontal = "hud-horizontal"
    case hudGrid = "hud-grid"
    case menuPopover = "menu-popover"

    var defaultGroupKey: ScreenshotFixtureGroupKey? {
        switch self {
        case .general, .backups, .menuPopover:
            return nil
        case .group:
            return .utilities
        case .hudHorizontal:
            return .info
        case .hudGrid:
            return .manyApps
        }
    }

    var baseCaptureDelay: TimeInterval {
        switch self {
        case .backups:
            return 1.2
        case .general, .group:
            return 0.8
        case .hudHorizontal, .hudGrid, .menuPopover:
            return 0.45
        }
    }

    var hidesWindowChrome: Bool {
        switch self {
        case .hudHorizontal, .hudGrid, .menuPopover:
            return true
        case .general, .group, .backups:
            return false
        }
    }

    var showsTrafficLightsOverlay: Bool {
        switch self {
        case .general, .group, .backups:
            return true
        case .hudHorizontal, .hudGrid, .menuPopover:
            return false
        }
    }
}

private enum ScreenshotFixtureGroupKey: String {
    case info
    case communication
    case productivity
    case utilities
    case media
    case manyApps = "many-apps"
}

private enum ScreenshotMenuVariant: String {
    case `default`
    case selected
}

private struct ScreenshotArguments {
    let scene: ScreenshotScene
    let theme: AppTheme
    let language: String
    let outputURL: URL
    let windowInfoURL: URL?
    let backgroundURL: URL?
    let groupKey: ScreenshotFixtureGroupKey?
    let menuVariant: ScreenshotMenuVariant

    var prefersLiveWindowCapture: Bool {
        windowInfoURL != nil
    }

    var captureDelay: TimeInterval {
        let themeSettleDelay: TimeInterval
        switch scene {
        case .general:
            themeSettleDelay = theme == .dark ? 0.55 : 0.2
        case .group:
            themeSettleDelay = theme == .dark ? 1.05 : 0.35
        case .backups:
            themeSettleDelay = theme == .dark ? 0.75 : 0.3
        case .hudHorizontal, .hudGrid, .menuPopover:
            themeSettleDelay = 0
        }

        return scene.baseCaptureDelay + themeSettleDelay
    }

    static let current = parse(CommandLine.arguments)

    private static func parse(_ arguments: [String]) -> ScreenshotArguments? {
        func value(for flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        guard let rawScene = value(for: "--screenshot-scene"),
              let scene = ScreenshotScene(rawValue: rawScene),
              let rawOutput = value(for: "--screenshot-output") else {
            return nil
        }

        let theme = AppTheme(rawValue: value(for: "--screenshot-theme") ?? "") ?? .light
        let language = value(for: "--screenshot-language") ?? "en"
        let windowInfoURL = value(for: "--screenshot-window-info").map { URL(fileURLWithPath: $0) }
        let backgroundURL = value(for: "--screenshot-background").map { URL(fileURLWithPath: $0) }
        let groupKey = value(for: "--screenshot-group").flatMap(ScreenshotFixtureGroupKey.init(rawValue:))
            ?? scene.defaultGroupKey
        let menuVariant = value(for: "--screenshot-variant").flatMap(ScreenshotMenuVariant.init(rawValue:))
            ?? .default

        return ScreenshotArguments(
            scene: scene,
            theme: theme,
            language: language,
            outputURL: URL(fileURLWithPath: rawOutput),
            windowInfoURL: windowInfoURL,
            backgroundURL: backgroundURL,
            groupKey: groupKey,
            menuVariant: menuVariant
        )
    }
}

private struct ScreenshotWindowInfo: Encodable {
    let windowNumber: Int
}

private enum ScreenshotRuntime {
    static let windowSize = CGSize(width: 1440, height: 900)
    static let outputPixelSize = CGSize(width: 2880, height: 1800)

    private static let screenshotShortcutKeys: [KeyboardShortcuts.Key] = [
        .one, .two, .three, .four, .five, .six
    ]

    static func primeDefaults(for arguments: ScreenshotArguments) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: WelcomeExperiencePolicy.hasDismissedWelcomeKey)
        defaults.set(true, forKey: WelcomeExperiencePolicy.hasAutoOpenedWelcomeSettingsKey)
        defaults.set(arguments.language, forKey: "selectedLanguage")
        defaults.set(arguments.theme.rawValue, forKey: "appTheme")
        defaults.set(true, forKey: "showHUD")
        defaults.set(true, forKey: "showShortcutInHUD")
        WelcomeExperiencePolicy.isScreenshotModeEnabled = true
        ScreenshotMode.renderStyle = arguments.prefersLiveWindowCapture ? .liveWindow : .synthetic
        LanguageManager.shared.syncAppleLanguages(for: arguments.language)
    }

    @MainActor
    static func seed(store: GroupStore, for arguments: ScreenshotArguments) {
        let groups = ScreenshotFixtureLibrary.makeGroups()
        RunningAppQuickAddCatalog.shared.setOverrideApps(ScreenshotFixtureLibrary.makeQuickAddOverrideApps())
        let export = ScreenshotFixtureLibrary.makeExport(
            groups: groups,
            theme: arguments.theme,
            language: arguments.language
        )
        store.applyImport(export)

        if let groupKey = arguments.groupKey,
           let groupID = ScreenshotFixtureLibrary.groupID(for: groupKey) {
            store.selectedGroupId = groupID
        }

        if arguments.scene == .backups {
            ScreenshotFixtureLibrary.writeBackupFixtures(
                into: store,
                groups: groups,
                language: arguments.language,
                theme: arguments.theme
            )
        }

        switch arguments.scene {
        case .general:
            ShortcutCycleURLNavigationState.request(tab: .general)
        case .group:
            ShortcutCycleURLNavigationState.request(tab: .groups)
        case .backups:
            ShortcutCycleURLNavigationState.request(tab: .general)
        case .hudHorizontal, .hudGrid, .menuPopover:
            break
        }
    }

    static func shortcutDataMap(for groups: [AppGroup]) -> [String: ShortcutData] {
        var shortcuts: [String: ShortcutData] = [:]

        for (index, group) in groups.enumerated() where screenshotShortcutKeys.indices.contains(index) {
            let shortcut = KeyboardShortcuts.Shortcut(screenshotShortcutKeys[index], modifiers: [.option])
            shortcuts[group.id.uuidString] = ShortcutData(
                carbonKeyCode: shortcut.carbonKeyCode,
                carbonModifiers: shortcut.carbonModifiers
            )
        }

        return shortcuts
    }

    @MainActor
    static func capture(window: NSWindow, arguments: ScreenshotArguments) async throws {
        prepare(window: window)

        let screenshot: CGImage
        do {
            if let liveSnapshot = try await systemSnapshot(window: window) {
                screenshot = liveSnapshot
            } else if let cachedSnapshot = snapshot(window: window) {
                screenshot = cachedSnapshot
            } else {
                throw ScreenshotError.captureFailed("Failed to snapshot screenshot window")
            }
        } catch {
            if let cachedSnapshot = snapshot(window: window) {
                fputs("Falling back to cached screenshot capture: \(error.localizedDescription)\n", stderr)
                screenshot = cachedSnapshot
            } else {
                throw error
            }
        }

        let composited = try compositeToOutputCanvas(cgImage: screenshot, theme: arguments.theme)
        try write(cgImage: composited, to: arguments.outputURL)
    }

    #if canImport(ScreenCaptureKit)
    @MainActor
    private static func systemSnapshot(window: NSWindow) async throws -> CGImage? {
        guard #available(macOS 14.4, *) else { return nil }

        let content = try await SCShareableContent.currentProcess
        guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            return nil
        }

        let scale = max(window.backingScaleFactor, 1)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = false
        configuration.shouldBeOpaque = false

        let backgroundColor = CGColor(gray: 0, alpha: 0)
        configuration.backgroundColor = backgroundColor

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(throwing: ScreenshotError.captureFailed("ScreenCaptureKit returned no image"))
            }
        }
    }
    #else
    @MainActor
    private static func systemSnapshot(window: NSWindow) async throws -> CGImage? {
        nil
    }
    #endif

    @MainActor
    static func prepareForExternalCapture(window: NSWindow, arguments: ScreenshotArguments) throws {
        prepare(window: window)

        guard let windowInfoURL = arguments.windowInfoURL else { return }
        let directory = windowInfoURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = ScreenshotWindowInfo(windowNumber: window.windowNumber)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: windowInfoURL, options: .atomic)
    }

    @MainActor
    private static func prepare(window: NSWindow) {
        window.orderFrontRegardless()
        if window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        }
        if window.canBecomeMain {
            window.makeMain()
        }
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    static func configure(window: NSWindow, for arguments: ScreenshotArguments) {
        let size = NSSize(width: windowSize.width, height: windowSize.height)
        let usesLiveWindowChrome = arguments.prefersLiveWindowCapture && !arguments.scene.hidesWindowChrome
        if let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let origin = NSPoint(
                x: screenFrame.midX - (size.width / 2),
                y: screenFrame.midY - (size.height / 2)
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        } else {
            window.setFrame(NSRect(origin: .zero, size: size), display: true)
            window.center()
        }

        window.appearance = {
            guard let colorScheme = arguments.theme.colorScheme else { return nil }

            switch colorScheme {
            case .dark:
                return NSAppearance(named: .darkAqua)
            case .light:
                return NSAppearance(named: .aqua)
            @unknown default:
                return nil
            }
        }()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = arguments.scene.hidesWindowChrome || !usesLiveWindowChrome
        window.isMovableByWindowBackground = false
        window.isOpaque = !arguments.scene.hidesWindowChrome
        window.backgroundColor = arguments.scene.hidesWindowChrome ? .clear : .windowBackgroundColor
        window.hasShadow = !arguments.scene.hidesWindowChrome
        window.sharingType = .readOnly
        if usesLiveWindowChrome {
            window.toolbarStyle = .unified
        }

        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for buttonType in buttons {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            button.isHidden = !usesLiveWindowChrome
            button.showsBorderOnlyWhileMouseInside = false
            button.needsDisplay = true
        }

        window.standardWindowButton(.closeButton)?.superview?.needsDisplay = true

        if arguments.scene.hidesWindowChrome {
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    static func ensureOutputDirectory(for outputURL: URL) throws {
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func write(cgImage: CGImage, to outputURL: URL) throws {
        try ensureOutputDirectory(for: outputURL)
        let representation = NSBitmapImageRep(cgImage: cgImage)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.captureFailed("Failed to encode PNG data")
        }
        try data.write(to: outputURL, options: .atomic)
    }

    @MainActor
    private static func snapshot(window: NSWindow) -> CGImage? {
        guard let targetView = window.contentView?.superview ?? window.contentView else {
            return nil
        }

        targetView.layoutSubtreeIfNeeded()
        let bounds = targetView.bounds
        guard let rep = targetView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        targetView.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    private static func compositeToOutputCanvas(cgImage: CGImage, theme: AppTheme) throws -> CGImage {
        let outputWidth = Int(outputPixelSize.width)
        let outputHeight = Int(outputPixelSize.height)

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenshotError.captureFailed("Failed to create output CGContext")
        }

        let fillColor = theme == .dark ? NSColor.black : NSColor.white
        context.setFillColor(fillColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

        let originX = (outputWidth - cgImage.width) / 2
        let originY = (outputHeight - cgImage.height) / 2
        context.draw(
            cgImage,
            in: CGRect(x: originX, y: originY, width: cgImage.width, height: cgImage.height)
        )

        guard let outputImage = context.makeImage() else {
            throw ScreenshotError.captureFailed("Failed to create output CGImage")
        }

        return outputImage
    }
}

private enum ScreenshotError: LocalizedError {
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureFailed(let message):
            return message
        }
    }
}

private enum ScreenshotFixtureLibrary {
    private struct FixtureApp {
        let name: String
        let bundleID: String
    }

    private struct FixtureGroup {
        let key: ScreenshotFixtureGroupKey
        let id: UUID
        let name: String
        let apps: [FixtureApp]
        let isEnabled: Bool
        let openAppIfNeeded: Bool
    }

    private static let fixtureGroups: [FixtureGroup] = [
        FixtureGroup(
            key: .info,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: "Info",
            apps: [
                .init(name: "Weather", bundleID: "com.apple.weather"),
                .init(name: "Maps", bundleID: "com.apple.Maps"),
                .init(name: "Stocks", bundleID: "com.apple.stocks"),
                .init(name: "News", bundleID: "com.apple.news")
            ],
            isEnabled: true,
            openAppIfNeeded: true
        ),
        FixtureGroup(
            key: .communication,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            name: "Communication",
            apps: [
                .init(name: "Messages", bundleID: "com.apple.MobileSMS"),
                .init(name: "FaceTime", bundleID: "com.apple.FaceTime"),
                .init(name: "Mail", bundleID: "com.apple.mail"),
                .init(name: "Contacts", bundleID: "com.apple.AddressBook")
            ],
            isEnabled: true,
            openAppIfNeeded: false
        ),
        FixtureGroup(
            key: .productivity,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            name: "Productivity",
            apps: [
                .init(name: "Calendar", bundleID: "com.apple.iCal"),
                .init(name: "Reminders", bundleID: "com.apple.reminders"),
                .init(name: "Notes", bundleID: "com.apple.Notes"),
                .init(name: "Freeform", bundleID: "com.apple.freeform"),
                .init(name: "Preview", bundleID: "com.apple.Preview")
            ],
            isEnabled: true,
            openAppIfNeeded: false
        ),
        FixtureGroup(
            key: .utilities,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            name: "Utilities",
            apps: [
                .init(name: "Terminal", bundleID: "com.apple.Terminal"),
                .init(name: "Activity Monitor", bundleID: "com.apple.ActivityMonitor"),
                .init(name: "Console", bundleID: "com.apple.Console"),
                .init(name: "System Settings", bundleID: "com.apple.systempreferences"),
                .init(name: "Calculator", bundleID: "com.apple.calculator"),
                .init(name: "Shortcuts", bundleID: "com.apple.shortcuts"),
                .init(name: "App Store", bundleID: "com.apple.AppStore"),
                .init(name: "QuickTime Player", bundleID: "com.apple.QuickTimePlayerX")
            ],
            isEnabled: true,
            openAppIfNeeded: true
        ),
        FixtureGroup(
            key: .media,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            name: "Media",
            apps: [
                .init(name: "Music", bundleID: "com.apple.Music"),
                .init(name: "TV", bundleID: "com.apple.TV"),
                .init(name: "Podcasts", bundleID: "com.apple.podcasts"),
                .init(name: "Photos", bundleID: "com.apple.Photos"),
                .init(name: "Books", bundleID: "com.apple.iBooksX")
            ],
            isEnabled: false,
            openAppIfNeeded: false
        ),
        FixtureGroup(
            key: .manyApps,
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
            name: "Many Apps",
            apps: [
                .init(name: "Weather", bundleID: "com.apple.weather"),
                .init(name: "Maps", bundleID: "com.apple.Maps"),
                .init(name: "Music", bundleID: "com.apple.Music"),
                .init(name: "TV", bundleID: "com.apple.TV"),
                .init(name: "Photos", bundleID: "com.apple.Photos"),
                .init(name: "Notes", bundleID: "com.apple.Notes"),
                .init(name: "Terminal", bundleID: "com.apple.Terminal"),
                .init(name: "System Settings", bundleID: "com.apple.systempreferences"),
                .init(name: "App Store", bundleID: "com.apple.AppStore"),
                .init(name: "Preview", bundleID: "com.apple.Preview")
            ],
            isEnabled: true,
            openAppIfNeeded: true
        )
    ]

    static func makeGroups() -> [AppGroup] {
        fixtureGroups.map { fixtureGroup in
            AppGroup(
                id: fixtureGroup.id,
                name: fixtureGroup.name,
                apps: fixtureGroup.apps.map(makeAppItem),
                isEnabled: fixtureGroup.isEnabled,
                openAppIfNeeded: fixtureGroup.openAppIfNeeded,
                lastModified: Date(timeIntervalSince1970: 1_735_689_600)
            )
        }
    }

    static func groupID(for key: ScreenshotFixtureGroupKey) -> UUID? {
        fixtureGroups.first(where: { $0.key == key })?.id
    }

    static func hudItems(for key: ScreenshotFixtureGroupKey) -> [HUDAppItem] {
        guard let group = fixtureGroups.first(where: { $0.key == key }) else { return [] }
        return group.apps.map { app in
            HUDAppItem(
                id: app.bundleID,
                name: app.name,
                icon: icon(for: app.bundleID),
                isRunning: true
            )
        }
    }

    static func hudCaptureState(for scene: ScreenshotScene, key: ScreenshotFixtureGroupKey) -> (items: [HUDAppItem], activeItemID: String, shortcut: String?) {
        let items = hudItems(for: key)
        let activeItemID: String

        switch scene {
        case .hudGrid:
            activeItemID = items.dropFirst(3).first?.id ?? items.first?.id ?? ""
        default:
            activeItemID = items.first?.id ?? ""
        }

        let shortcut: String?
        if let index = items.firstIndex(where: { $0.id == activeItemID }) {
            shortcut = "⌥\(index + 1)"
        } else {
            shortcut = nil
        }

        return (items, activeItemID, shortcut)
    }

    static func menuRunningBundleIDs() -> Set<String> {
        Set(
            fixtureGroups
                .filter(\.isEnabled)
                .flatMap { group in group.apps.map(\.bundleID) }
        )
    }

    static func makeQuickAddOverrideApps() -> [AppItem] {
        var seenBundleIDs = Set<String>()
        return fixtureGroups
            .flatMap(\.apps)
            .filter { seenBundleIDs.insert($0.bundleID).inserted }
            .map(makeAppItem)
            .sorted {
                let lhs = $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                let rhs = $1.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                if lhs == rhs {
                    return $0.bundleIdentifier < $1.bundleIdentifier
                }
                return lhs < rhs
            }
    }

    static func makeExport(groups: [AppGroup], theme: AppTheme, language: String) -> SettingsExport {
        SettingsExport(
            groups: groups,
            settings: AppSettings(
                showHUD: true,
                showShortcutInHUD: true,
                selectedLanguage: language,
                appTheme: theme.rawValue
            ),
            shortcuts: ScreenshotRuntime.shortcutDataMap(for: groups)
        )
    }

    @MainActor
    static func writeBackupFixtures(
        into store: GroupStore,
        groups: [AppGroup],
        language: String,
        theme: AppTheme
    ) {
        let fileManager = FileManager.default
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        try? fileManager.removeItem(at: store.backupDirectory)
        try? fileManager.createDirectory(at: store.backupDirectory, withIntermediateDirectories: true)

        let comparisonGroups = groups.enumerated().map { index, group -> AppGroup in
            guard index == 0 else { return group }
            var updatedGroup = group
            updatedGroup.apps = Array(group.apps.dropLast())
            return updatedGroup
        }

        let exports: [(name: String, export: SettingsExport, createdAt: Date)] = [
            (
                "backup 2026-02-02 17-46-00.json",
                makeExport(groups: comparisonGroups, theme: theme == .dark ? .light : .dark, language: language),
                Date(timeIntervalSince1970: 1_770_074_760)
            ),
            (
                "backup 2026-02-02 17-52-00.json",
                makeExport(groups: groups, theme: theme, language: language),
                Date(timeIntervalSince1970: 1_770_075_120)
            )
        ]

        for exportFile in exports {
            let fileURL = store.backupDirectory.appendingPathComponent(exportFile.name)
            guard let data = try? encoder.encode(exportFile.export) else { continue }
            try? data.write(to: fileURL, options: .atomic)
            try? fileManager.setAttributes([.creationDate: exportFile.createdAt], ofItemAtPath: fileURL.path)
        }
    }

    private static func makeAppItem(from definition: FixtureApp) -> AppItem {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: definition.bundleID)
        return AppItem(
            bundleIdentifier: definition.bundleID,
            name: definition.name,
            iconPath: appURL?.path
        )
    }

    private static func icon(for bundleID: String) -> NSImage {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

private struct ScreenshotSceneContainerView: View {
    @EnvironmentObject private var store: GroupStore

    let arguments: ScreenshotArguments
    let localeObserver: LocaleObserver

    var body: some View {
        Group {
            if ScreenshotMode.usesSyntheticControls {
                content
                    .tint(.accentColor)
            } else {
                content
            }
        }
            .environment(\.controlActiveState, .key)
            .overlay(alignment: .topLeading) {
                if arguments.scene.showsTrafficLightsOverlay && ScreenshotMode.usesSyntheticChrome {
                    ScreenshotTrafficLightsOverlay()
                        .padding(.top, 14)
                        .padding(.leading, 16)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch arguments.scene {
        case .general:
            if arguments.prefersLiveWindowCapture {
                MainView()
                    .environmentObject(store)
                    .environmentObject(localeObserver)
            } else {
                ScreenshotGeneralSceneView(localeObserver: localeObserver)
                    .environmentObject(store)
            }
        case .group:
            if arguments.prefersLiveWindowCapture {
                MainView()
                    .environmentObject(store)
                    .environmentObject(localeObserver)
            } else {
                ScreenshotGroupSceneView()
                    .environmentObject(store)
            }
        case .backups:
            if arguments.prefersLiveWindowCapture {
                MainView()
                    .environmentObject(store)
                    .environmentObject(localeObserver)
            } else {
                ScreenshotBackupSceneView(localeObserver: localeObserver)
                    .environmentObject(store)
            }
        case .hudHorizontal, .hudGrid:
            ScreenshotHUDSceneView(arguments: arguments)
        case .menuPopover:
            ScreenshotMenuPopoverSceneView(arguments: arguments)
                .environmentObject(store)
        }
    }
}

@MainActor
private enum ScreenshotWindowLifecycle {
    static var store: GroupStore?
    static var controller: NSWindowController?

    static func configure(store: GroupStore) {
        self.store = store
    }

    static func present(arguments: ScreenshotArguments) {
        guard let store else { return }

        if arguments.prefersLiveWindowCapture {
            switch arguments.scene {
            case .general:
                ShortcutCycleURLNavigationState.request(tab: .general)
            case .group:
                ShortcutCycleURLNavigationState.request(tab: .groups)
            case .backups:
                ShortcutCycleURLNavigationState.requestBackupBrowser()
            case .hudHorizontal, .hudGrid, .menuPopover:
                break
            }
        }

        let captureWindow: NSWindow
        switch arguments.scene {
        case .hudHorizontal where arguments.prefersLiveWindowCapture,
             .hudGrid where arguments.prefersLiveWindowCapture:
            self.controller = nil
            captureWindow = presentLiveHUDWindow(arguments: arguments)
        case .menuPopover where arguments.prefersLiveWindowCapture:
            captureWindow = presentLiveMenuPopoverWindow(arguments: arguments, store: store)
        default:
            captureWindow = presentSceneWindow(arguments: arguments, store: store)
        }

        let timeout = arguments.windowInfoURL == nil
            ? max(arguments.captureDelay + 4, 8.0)
            : max(arguments.captureDelay + 20, 25.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + arguments.captureDelay) {
            Task { @MainActor in
                do {
                    if arguments.windowInfoURL != nil {
                        try ScreenshotRuntime.prepareForExternalCapture(window: captureWindow, arguments: arguments)
                    } else {
                        try await ScreenshotRuntime.capture(window: captureWindow, arguments: arguments)
                        exit(0)
                    }
                } catch {
                    fputs("Screenshot capture failed: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            fputs("Screenshot capture timed out for scene \(arguments.scene.rawValue)\n", stderr)
            exit(2)
        }
    }

    private static func presentSceneWindow(arguments: ScreenshotArguments, store: GroupStore) -> NSWindow {
        let rootView = ScreenshotSceneContainerView(
            arguments: arguments,
            localeObserver: LocaleObserver()
        )
        .environmentObject(store)

        let hostingController = NSHostingController(rootView: rootView)
        let styleMask: NSWindow.StyleMask = arguments.scene.hidesWindowChrome
            ? [.borderless]
            : [.titled, .closable, .miniaturizable]
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ScreenshotRuntime.windowSize.width,
                height: ScreenshotRuntime.windowSize.height
            ),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.title = arguments.prefersLiveWindowCapture ? "Shortcut Cycle" : "ShortcutCycle Screenshot"
        window.isMovable = false

        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        ScreenshotRuntime.configure(window: window, for: arguments)
        return window
    }

    private static func presentLiveHUDWindow(arguments: ScreenshotArguments) -> NSWindow {
        let groupKey = arguments.groupKey ?? arguments.scene.defaultGroupKey ?? .info
        let hudCapture = ScreenshotFixtureLibrary.hudCaptureState(for: arguments.scene, key: groupKey)

        guard let window = HUDManager.shared.presentScreenshotHUD(
            items: hudCapture.items,
            activeAppId: hudCapture.activeItemID,
            shortcut: hudCapture.shortcut
        ) else {
            fatalError("Failed to create HUD screenshot window")
        }

        return window
    }

    private static func presentLiveMenuPopoverWindow(arguments: ScreenshotArguments, store: GroupStore) -> NSWindow {
        let selectedGroupID: UUID? = {
            switch arguments.menuVariant {
            case .default:
                return nil
            case .selected:
                return arguments.groupKey.flatMap(ScreenshotFixtureLibrary.groupID(for:))
                    ?? ScreenshotFixtureLibrary.groupID(for: .utilities)
            }
        }()

        let rootView = MenuBarView(
            selectedLanguage: arguments.language,
            screenshotHighlightedGroupID: selectedGroupID,
            screenshotRunningBundleIDs: ScreenshotFixtureLibrary.menuRunningBundleIDs(),
            screenshotLaunchAtLogin: true,
            screenshotThemeOverride: arguments.theme
        )
        .environment(\.controlActiveState, .key)
        .environmentObject(store)

        let hostingController = NSHostingController(rootView: rootView)
        let window = ScreenshotPopoverCaptureWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 280, height: 400)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.isMovable = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.sharingType = .readOnly

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        if fittingSize.width > 0, fittingSize.height > 0 {
            window.setContentSize(fittingSize)
        }

        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()
        return window
    }
}

private final class ScreenshotPopoverCaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct ScreenshotBackupSceneView: View {
    @EnvironmentObject private var store: GroupStore
    @Environment(\.colorScheme) private var colorScheme

    let localeObserver: LocaleObserver

    var body: some View {
        ZStack {
            ScreenshotGeneralSceneView(localeObserver: localeObserver)
                .environmentObject(store)
                .allowsHitTesting(false)

            Color.black.opacity(colorScheme == .dark ? 0.10 : 0.08)
                .ignoresSafeArea()

            BackupBrowserView()
                .environmentObject(store)
                .frame(width: 650, height: 450)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.38 : 0.18),
                    radius: colorScheme == .dark ? 42 : 30,
                    x: 0,
                    y: colorScheme == .dark ? 18 : 12
                )
        }
    }
}

private struct ScreenshotGeneralSceneView: View {
    @EnvironmentObject private var store: GroupStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"

    let localeObserver: LocaleObserver

    var body: some View {
        ScreenshotSettingsWindowChrome(selectedLanguage: selectedLanguage, selectedTab: .general) {
            GeneralSettingsView()
                .environmentObject(store)
                .environmentObject(localeObserver)
        }
        .background(SettingsChromePalette.windowBackground(for: colorScheme))
    }
}

private struct ScreenshotTrafficLightsOverlay: View {
    private let colors: [Color] = [
        Color(red: 1.0, green: 0.37, blue: 0.34),
        Color(red: 1.0, green: 0.74, blue: 0.18),
        Color(red: 0.18, green: 0.82, blue: 0.35)
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(colors.indices, id: \.self) { index in
                Circle()
                    .fill(colors[index])
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                    )
            }
        }
    }
}

private struct ScreenshotGroupSceneView: View {
    @EnvironmentObject private var store: GroupStore
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @Environment(\.colorScheme) private var colorScheme

    private var selectedGroupID: UUID? {
        store.selectedGroupId ?? store.groups.first?.id
    }

    var body: some View {
        ScreenshotSettingsWindowChrome(selectedLanguage: selectedLanguage, selectedTab: .groups) {
            HStack(spacing: 0) {
                ScreenshotGroupSidebar(selectedGroupID: selectedGroupID)
                    .frame(width: 220)

                Divider()

                if let selectedGroupID {
                    GroupEditView(groupId: selectedGroupID)
                        .environmentObject(store)
                } else {
                    Color.clear
                }
            }
        }
        .background(SettingsChromePalette.windowBackground(for: colorScheme))
    }
}

private struct ScreenshotSettingsWindowChrome<Content: View>: View {
    let selectedLanguage: String
    let selectedTab: ScreenshotSettingsTabsView.Tab
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                ScreenshotSettingsTabsView(selectedLanguage: selectedLanguage, selectedTab: selectedTab)
                Spacer()
            }
            .frame(height: 42)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            content()
        }
    }
}

private struct ScreenshotSettingsTabsView: View {
    enum Tab {
        case groups
        case general
    }

    let selectedLanguage: String
    let selectedTab: Tab

    var body: some View {
        HStack(spacing: 4) {
            tab("Groups".localized(language: selectedLanguage), isSelected: selectedTab == .groups)
            tab("General".localized(language: selectedLanguage), isSelected: selectedTab == .general)
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private func tab(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : .clear)
            )
    }
}

private struct ScreenshotGroupSidebar: View {
    @EnvironmentObject private var store: GroupStore
    @Environment(\.colorScheme) private var colorScheme

    let selectedGroupID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.groups) { group in
                        ScreenshotGroupSidebarRow(
                            group: group,
                            isSelected: group.id == selectedGroupID
                        )
                    }
                }
                .padding(10)
            }

            Divider()

            HStack {
                Label("Add Group", systemImage: "plus")
                    .font(.body)
                Spacer()
            }
            .padding(10)
        }
        .background(SettingsChromePalette.sidebarBackground(for: colorScheme))
    }
}

private struct ScreenshotGroupSidebarRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"

    let group: AppGroup
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if ScreenshotMode.usesSyntheticControls {
                ScreenshotAccentSwitch(isOn: group.isEnabled, size: .mini)
            } else {
                Toggle("", isOn: .constant(group.isEnabled))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                    .controlSize(.mini)
            }

            Image(systemName: "folder.fill")
                .foregroundStyle(group.isEnabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(group.isEnabled ? .primary : .secondary)
                    .lineLimit(1)

                if let shortcut = group.shortcutDisplayString {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SettingsChromePalette.chipFill(for: colorScheme))
                        .clipShape(Capsule(style: .continuous))
                } else {
                    Text("No shortcut".localized(language: selectedLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text("\(group.apps.count)")
                .font(colorScheme == .dark ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(SettingsChromePalette.badgeFill(for: colorScheme)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? SettingsChromePalette.neutralHoverFill(for: colorScheme)
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected ? SettingsChromePalette.neutralHoverBorder(for: colorScheme) : Color.clear,
                    lineWidth: 1
                )
        )
        .opacity(group.isEnabled ? 1.0 : 0.68)
    }
}

private struct ScreenshotHUDSceneView: View {
    let arguments: ScreenshotArguments

    private var items: [HUDAppItem] {
        ScreenshotFixtureLibrary.hudItems(for: arguments.groupKey ?? .info)
    }

    private var activeItemID: String {
        switch arguments.scene {
        case .hudGrid:
            return items.dropFirst(3).first?.id ?? items.first?.id ?? ""
        default:
            return items.first?.id ?? ""
        }
    }

    var body: some View {
        ZStack {
            ScreenshotBackdrop(theme: arguments.theme, backgroundURL: arguments.backgroundURL)
            AppSwitcherHUDView(
                apps: items,
                activeAppId: activeItemID,
                shortcutString: "⌥\(items.firstIndex(where: { $0.id == activeItemID }).map { String($0 + 1) } ?? "1")"
            )
            .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(arguments.theme.colorScheme)
    }
}

private struct ScreenshotBackdrop: View {
    let theme: AppTheme
    let backgroundURL: URL?

    private var backgroundImage: NSImage? {
        guard let backgroundURL else { return nil }
        return NSImage(contentsOf: backgroundURL)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let backgroundImage {
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ForEach(backgroundShapes.indices, id: \.self) { index in
                        Circle()
                            .fill(backgroundShapes[index].color)
                            .frame(width: backgroundShapes[index].size, height: backgroundShapes[index].size)
                            .blur(radius: 40)
                            .offset(backgroundShapes[index].offset)
                    }
                }
            }
        }
    }

    private var gradientColors: [Color] {
        if theme == .dark {
            return [
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.12, green: 0.16, blue: 0.25),
                Color(red: 0.10, green: 0.23, blue: 0.29)
            ]
        }

        return [
            Color(red: 0.91, green: 0.96, blue: 1.0),
            Color(red: 0.84, green: 0.92, blue: 0.98),
            Color(red: 0.93, green: 0.96, blue: 0.89)
        ]
    }

    private var backgroundShapes: [(size: CGFloat, offset: CGSize, color: Color)] {
        if theme == .dark {
            return [
                (420, CGSize(width: -380, height: -240), Color.cyan.opacity(0.18)),
                (320, CGSize(width: 360, height: -180), Color.blue.opacity(0.18)),
                (500, CGSize(width: 280, height: 260), Color.green.opacity(0.12))
            ]
        }

        return [
            (420, CGSize(width: -360, height: -260), Color.white.opacity(0.55)),
            (300, CGSize(width: 320, height: -160), Color.cyan.opacity(0.22)),
            (440, CGSize(width: 260, height: 260), Color.green.opacity(0.18))
        ]
    }
}

private struct ScreenshotMenuPopoverSceneView: View {
    @EnvironmentObject private var store: GroupStore

    let arguments: ScreenshotArguments

    private var selectedGroupID: UUID? {
        switch arguments.menuVariant {
        case .default:
            return nil
        case .selected:
            return arguments.groupKey.flatMap(ScreenshotFixtureLibrary.groupID(for:))
                ?? ScreenshotFixtureLibrary.groupID(for: .utilities)
        }
    }

    var body: some View {
        ZStack {
            Color(nsColor: arguments.theme == .dark ? .windowBackgroundColor : .underPageBackgroundColor)
                .ignoresSafeArea()

            VStack {
                Spacer(minLength: 90)
                MenuBarView(
                    selectedLanguage: arguments.language,
                    screenshotHighlightedGroupID: selectedGroupID,
                    screenshotLaunchAtLogin: true,
                    screenshotThemeOverride: arguments.theme
                )
                .fixedSize()
                .environmentObject(store)
                Spacer()
            }
        }
        .preferredColorScheme(arguments.theme.colorScheme)
    }
}


@main
struct ShortcutCycleApp: App {
    @StateObject private var store: GroupStore
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @StateObject private var localeObserver = LocaleObserver()

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if let screenshotArguments = ScreenshotArguments.current {
            ScreenshotRuntime.primeDefaults(for: screenshotArguments)
            LaunchAtLoginManager.setScreenshotOverride(isEnabled: true)

            let screenshotStore = GroupStore(
                userDefaults: .standard,
                backupDebounceInterval: 3600,
                saveDebounceInterval: 0,
                autoBackupEnabled: false
            )
            ScreenshotRuntime.seed(store: screenshotStore, for: screenshotArguments)
            ScreenshotWindowLifecycle.configure(store: screenshotStore)
            _store = StateObject(wrappedValue: screenshotStore)
        } else {
            WelcomeExperiencePolicy.isScreenshotModeEnabled = false
            LaunchAtLoginManager.setScreenshotOverride(isEnabled: nil)
            RunningAppQuickAddCatalog.shared.setOverrideApps(nil)
            _store = StateObject(wrappedValue: GroupStore.shared)

            // Setup shortcut manager
            Task { @MainActor in
                ShortcutManager.shared.registerAllShortcuts()
            }
        }
        // Sync AppleLanguages so third-party bundles (e.g. KeyboardShortcuts) use the
        // correct locale. Must run before any view creates a KeyboardShortcuts.Recorder.
        let selected = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system"
        LanguageManager.shared.syncAppleLanguages(for: selected)
    }

    var body: some Scene {
        // Menu bar extra
        MenuBarExtra(
            "Shortcut Cycle",
            systemImage: "command.square.fill",
            isInserted: .constant(ScreenshotArguments.current == nil)
        ) {
            MenuBarView(selectedLanguage: selectedLanguage)
                .environmentObject(store)
                .id("\(selectedLanguage)-\(localeObserver.id)") // Force redraw on language or system locale change
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Window("Shortcut Cycle", id: "settings") {
            MainView()
                .environmentObject(store)
                .environmentObject(localeObserver)
        }
        .defaultSize(width: 700, height: 500)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AppCommands()
        }
    }


}


@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasEvaluatedInitialManualActivation = false
    private var suppressAutomaticWelcomeForCurrentLaunch = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        if ScreenshotArguments.current != nil {
            NSApp.setActivationPolicy(.regular)
        } else {
            // Run as a menu bar app (no dock icon)
            NSApp.setActivationPolicy(.accessory)
        }

        // Register for URL events directly via Apple Events.
        // This is more reliable than application(_:open:) or .onOpenURL,
        // which can fail when a SwiftUI Window is already the key window.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard ScreenshotArguments.current == nil else { return }
        guard !hasEvaluatedInitialManualActivation else { return }
        hasEvaluatedInitialManualActivation = true

        if WelcomeExperiencePolicy.prepareAutomaticSettingsOpenIfNeeded(
            suppressForCurrentLaunch: suppressAutomaticWelcomeForCurrentLaunch
        ) {
            ShortcutCycleURLRouter.openSettingsFromOutsideView(tab: .groups)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screenshotArguments = ScreenshotArguments.current else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ScreenshotWindowLifecycle.present(arguments: screenshotArguments)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard ScreenshotArguments.current == nil else { return false }
        guard !flag else { return false }
        ShortcutCycleURLRouter.openSettingsFromOutsideView()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func handleURLEvent(
        _ event: NSAppleEventDescriptor,
        withReply reply: NSAppleEventDescriptor
    ) {
        guard ScreenshotArguments.current == nil else { return }
        // Apple Events are delivered before applicationDidBecomeActive on a URL-scheme
        // cold launch, so setting this flag here reliably prevents auto-open of Settings
        // when the launch was triggered externally (e.g. shortcutcycle:// URL).
        suppressAutomaticWelcomeForCurrentLaunch = true
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        ShortcutCycleURLRouter.handle(url)
    }
}


// MARK: - Theme Manager

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    // For icon in menu
    var icon: String {
        switch self {
        case .system: return "display"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    func toggledAppearance(using effectiveAppearanceName: NSAppearance.Name?) -> AppTheme {
        let isCurrentlyDark: Bool

        switch self {
        case .light:
            isCurrentlyDark = false
        case .dark:
            isCurrentlyDark = true
        case .system:
            isCurrentlyDark = effectiveAppearanceName == .darkAqua
        }

        return isCurrentlyDark ? .light : .dark
    }
}

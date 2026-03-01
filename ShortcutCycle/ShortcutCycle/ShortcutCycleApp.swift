import SwiftUI
import KeyboardShortcuts
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


// MARK: - App Commands

struct AppCommands: Commands {
    @FocusedBinding(\.selectedTab) private var selectedTab

    private var groupsDisabled: Bool {
        selectedTab != "groups" || GroupStore.shared.groups.count < 2
    }

    var body: some Commands {
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
        }
    }

    private func selectPreviousGroup() {
        let store = GroupStore.shared
        guard store.groups.count >= 2 else { return }
        guard let currentId = store.selectedGroupId,
              let currentIndex = store.groups.firstIndex(where: { $0.id == currentId }) else {
            store.selectedGroupId = store.groups.first?.id
            return
        }
        let previousIndex = currentIndex == 0 ? store.groups.count - 1 : currentIndex - 1
        store.selectedGroupId = store.groups[previousIndex].id
    }

    private func selectNextGroup() {
        let store = GroupStore.shared
        guard store.groups.count >= 2 else { return }
        guard let currentId = store.selectedGroupId,
              let currentIndex = store.groups.firstIndex(where: { $0.id == currentId }) else {
            store.selectedGroupId = store.groups.first?.id
            return
        }
        let nextIndex = currentIndex == store.groups.count - 1 ? 0 : currentIndex + 1
        store.selectedGroupId = store.groups[nextIndex].id
    }
}


// MARK: - Settings Window Observer

/// Switches activation policy back to .accessory when the settings window closes,
/// restoring the menu-bar-only appearance.
struct SettingsWindowObserver: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.observe(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class Coordinator {
        private var observer: NSObjectProtocol?

        func observe(window: NSWindow) {
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }

        deinit {
            if let o = observer {
                NotificationCenter.default.removeObserver(o)
            }
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
    static func handle(_ url: URL) {
        guard let command = ShortcutCycleURLParser.parse(url) else { return }

        let store = GroupStore.shared

        switch command {
        case .openSettings(let tab):
            openSettingsWindow(tab: tab)
        case .openBackupBrowser:
            openBackupBrowser()
        case .cycle(let target):
            guard let group = resolveGroup(target, in: store),
                  group.isEnabled else {
                return
            }
            store.selectedGroupId = group.id
            AppSwitcher.shared.handleShortcut(for: group, store: store)
        case .selectGroup(let target):
            guard let group = resolveGroup(target, in: store) else { return }
            store.selectedGroupId = group.id
        case .enableGroup(let target):
            setGroupEnabledState(true, for: target, store: store)
        case .disableGroup(let target):
            setGroupEnabledState(false, for: target, store: store)
        case .toggleGroup(let target):
            guard let group = resolveGroup(target, in: store) else { return }
            store.toggleGroupEnabled(group)
        case .backup:
            _ = store.manualBackup()
        case .flushAutoSave:
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
            guard let group = resolveGroup(target, in: store) else { return }
            let alert = NSAlert()
            alert.messageText = "Delete '\(group.name)'?"
            alert.informativeText = "This will permanently remove the group and its shortcut."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            store.deleteGroup(group)
        case .renameGroup(let target, let newName):
            guard let group = resolveGroup(target, in: store) else { return }
            store.renameGroup(group, newName: newName)
        case .reorderGroup(let target, let position):
            guard let group = resolveGroup(target, in: store) else { return }
            guard let currentIndex = store.groups.firstIndex(where: { $0.id == group.id }) else { return }
            let clampedDestination = min(max(position - 1, 0), store.groups.count - 1)
            let toOffset = clampedDestination > currentIndex ? clampedDestination + 1 : clampedDestination
            store.moveGroups(from: IndexSet(integer: currentIndex), to: toOffset)
        case .addApp(let target, let bundleId):
            guard let group = resolveGroup(target, in: store) else { return }
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
                  let appItem = AppItem.from(appURL: appURL) else {
                return
            }
            store.addApp(appItem, to: group.id)
        case .removeApp(let target, let bundleId):
            guard let group = resolveGroup(target, in: store) else { return }
            guard let appItem = group.apps.first(where: { $0.bundleIdentifier == bundleId }) else { return }
            store.removeApp(appItem, from: group.id)
        case .listGroups(let output):
            let groupsData = store.groups.enumerated().map { index, group in
                [
                    "id": group.id.uuidString,
                    "name": group.name,
                    "isEnabled": group.isEnabled,
                    "appCount": group.apps.count,
                    "index": index + 1
                ] as [String: Any]
            }
            writeQueryResult(groupsData, command: "list-groups", to: output)
        case .getGroup(let target, let output):
            guard let group = resolveGroup(target, in: store) else { return }
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
            writeQueryResult(groupData, command: "get-group", to: output)
        }
    }

    private static func openSettingsWindow(tab: URLSettingsTab?) {
        if let tab {
            ShortcutCycleURLNavigationState.request(tab: tab)
        }

        if let settingsWindow = NSApp.windows.first(where: { window in
            window.identifier?.rawValue == "settings"
        }) {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if let tab {
                NotificationCenter.default.post(
                    name: .settingsTabRequested,
                    object: tab.rawValue
                )
            }
            return
        }

        NotificationCenter.default.post(name: Notification.Name("ToggleSettingsWindow"), object: nil)
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

    private static func setGroupEnabledState(_ isEnabled: Bool, for target: URLGroupTarget, store: GroupStore) {
        guard var group = resolveGroup(target, in: store) else { return }
        guard group.isEnabled != isEnabled else { return }

        group.isEnabled = isEnabled
        store.updateGroup(group)
        NotificationCenter.default.post(name: .shortcutsNeedUpdate, object: nil)
    }

    private static func resolveGroup(_ target: URLGroupTarget?, in store: GroupStore) -> AppGroup? {
        guard let target else {
            if let selectedGroup = store.selectedGroup, selectedGroup.isEnabled {
                return selectedGroup
            }
            return store.groups.first(where: \.isEnabled)
        }

        switch target {
        case .id(let id):
            return store.groups.first(where: { $0.id == id })
        case .name(let name):
            return store.groups.first(where: {
                $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            })
        case .index(let index):
            let resolvedIndex = index - 1
            guard store.groups.indices.contains(resolvedIndex) else { return nil }
            return store.groups[resolvedIndex]
        }
    }

    private static func applySetting(key: String, value: String) {
        switch key {
        case "showhud", "hud":
            guard let boolValue = parseBool(value) else { return }
            UserDefaults.standard.set(boolValue, forKey: "showHUD")
        case "showshortcutinhud", "hudshortcut", "showshortcut":
            guard let boolValue = parseBool(value) else { return }
            UserDefaults.standard.set(boolValue, forKey: "showShortcutInHUD")
        case "apptheme", "theme", "appearance":
            guard let theme = parseTheme(value) else { return }
            UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
        case "selectedlanguage", "language":
            guard let language = parseLanguage(value) else { return }
            UserDefaults.standard.set(language, forKey: "selectedLanguage")
        case "openatlogin", "launchatlogin":
            guard let boolValue = parseBool(value) else { return }
            LaunchAtLoginManager.shared.isEnabled = boolValue
        default:
            break
        }
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on", "enabled":
            return true
        case "0", "false", "no", "off", "disabled":
            return false
        default:
            return nil
        }
    }

    private static func parseTheme(_ value: String) -> AppTheme? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "system", "default":
            return .system
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    private static func parseLanguage(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("system") == .orderedSame {
            return "system"
        }

        let supported = LanguageManager.shared.supportedLanguages.map { $0.code.lowercased() }
        let candidate = trimmed.lowercased()
        if supported.contains(candidate) {
            // Preserve canonical casing from supported list (e.g., pt-BR, zh-Hans)
            return LanguageManager.shared.supportedLanguages.first(where: {
                $0.code.lowercased() == candidate
            })?.code
        }
        return nil
    }

    private static func exportSettings(to rawPath: String, store: GroupStore) {
        guard let fileURL = fileURL(from: rawPath) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let alert = NSAlert()
            alert.messageText = "Overwrite Existing File?"
            alert.informativeText = "A file already exists at \(fileURL.path). Do you want to replace it?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            let data = try store.exportData()
            let parentDirectory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to export settings to \(fileURL.path): \(error)")
        }
    }

    private static func importSettings(from rawPath: String, store: GroupStore) {
        guard let fileURL = fileURL(from: rawPath) else { return }

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
            print("Failed to import settings from \(fileURL.path): \(error)")
        }
    }

    private static func restoreBackup(target: URLBackupTarget?, store: GroupStore) {
        guard let backupURL = resolveBackupURL(target: target, store: store) else { return }
        guard let data = try? Data(contentsOf: backupURL) else { return }

        let alert = NSAlert()
        alert.messageText = "Restore Backup?"
        alert.informativeText = "This will replace all current groups and settings with the backup from \(backupURL.lastPathComponent)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        switch SettingsExport.validate(data: data) {
        case .success(let export):
            store.applyImport(export)
        case .failure(let error):
            print("Failed to restore backup from \(backupURL.path): \(error.localizedDescription)")
        }
    }

    private static func resolveBackupURL(target: URLBackupTarget?, store: GroupStore) -> URL? {
        switch target {
        case .path(let path):
            return fileURL(from: path)
        case .name(let name):
            return store.backupDirectory.appendingPathComponent(name)
        case .index(let index):
            let backups = sortedBackupFiles(in: store.backupDirectory)
            let resolvedIndex = index - 1
            guard backups.indices.contains(resolvedIndex) else { return nil }
            return backups[resolvedIndex]
        case nil:
            return sortedBackupFiles(in: store.backupDirectory).first
        }
    }

    private static func sortedBackupFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return leftDate > rightDate
            }
    }

    private static func writeQueryResult(_ data: Any, command: String, to outputPath: String) {
        let result: [String: Any] = [
            "command": command,
            "success": true,
            "data": data
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        let parentDir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try? jsonData.write(to: url, options: .atomic)
    }

    private static func fileURL(from rawPath: String) -> URL? {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        if let candidate = URL(string: path), candidate.isFileURL {
            return candidate
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath)
        }

        let cwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: cwd).appendingPathComponent(expandedPath)
    }
}


@main
struct ShortcutCycleApp: App {
    @StateObject private var store = GroupStore.shared
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @StateObject private var localeObserver = LocaleObserver()

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Setup shortcut manager
        Task { @MainActor in
            ShortcutManager.shared.registerAllShortcuts()
        }
    }

    var body: some Scene {
        // Menu bar extra
        MenuBarExtra("Shortcut Cycle", systemImage: "command.square.fill") {
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
        .commands {
            AppCommands()
        }
    }


}


@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Run as a menu bar app (no dock icon)
        NSApp.setActivationPolicy(.accessory)

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

    @objc private func handleURLEvent(
        _ event: NSAppleEventDescriptor,
        withReply reply: NSAppleEventDescriptor
    ) {
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
}

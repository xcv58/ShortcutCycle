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

enum URLGroupTarget: Equatable {
    case id(UUID)
    case name(String)
    case index(Int) // 1-based index for user-facing URLs
}

enum URLSettingsTab: String, Equatable {
    case groups
    case general
}

enum URLBackupTarget: Equatable {
    case index(Int) // 1-based index (1 = most recent backup)
    case name(String)
    case path(String)
}

enum ShortcutCycleURLCommand: Equatable {
    case openSettings(URLSettingsTab?)
    case openBackupBrowser
    case cycle(URLGroupTarget?)
    case selectGroup(URLGroupTarget)
    case enableGroup(URLGroupTarget)
    case disableGroup(URLGroupTarget)
    case toggleGroup(URLGroupTarget)
    case backup
    case flushAutoSave
    case setSetting(key: String, value: String)
    case exportSettings(path: String)
    case importSettings(path: String)
    case restoreBackup(URLBackupTarget?)
}

enum ShortcutCycleURLParser {
    static let scheme = "shortcutcycle"

    static func parse(_ url: URL) -> ShortcutCycleURLCommand? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard let action = resolveAction(from: components) else { return nil }

        let query = queryDictionary(from: components)
        let target = parseGroupTarget(from: query)

        switch action {
        case "settings", "open-settings":
            if shouldOpenBackupBrowser(from: query) {
                return .openBackupBrowser
            }
            return .openSettings(parseSettingsTab(from: query))
        case "open-backup-browser", "backup-browser", "automatic-backups":
            return .openBackupBrowser
        case "cycle":
            return .cycle(target)
        case "select-group":
            guard let target else { return nil }
            return .selectGroup(target)
        case "enable-group":
            guard let target else { return nil }
            return .enableGroup(target)
        case "disable-group":
            guard let target else { return nil }
            return .disableGroup(target)
        case "toggle-group":
            guard let target else { return nil }
            return .toggleGroup(target)
        case "backup":
            return .backup
        case "flush-auto-save", "flush-auto-backup", "trigger-auto-save", "trigger-auto-backup", "autosave":
            return .flushAutoSave
        case "set-setting":
            guard let key = (query["key"] ?? query["name"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty,
                  let value = (query["value"] ?? query["v"])?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return nil
            }
            return .setSetting(key: key.lowercased(), value: value)
        case "export-settings", "export":
            guard let path = parsePathValue(from: query) else { return nil }
            return .exportSettings(path: path)
        case "import-settings", "import":
            guard let path = parsePathValue(from: query) else { return nil }
            return .importSettings(path: path)
        case "restore-backup", "restore":
            return .restoreBackup(parseBackupTarget(from: query))
        default:
            return nil
        }
    }

    private static func resolveAction(from components: URLComponents) -> String? {
        let host = components.host?.lowercased()
        let pathComponents = components.path
            .split(separator: "/")
            .map { $0.lowercased() }

        // Support x-callback style:
        // shortcutcycle://x-callback-url/cycle?group=Browsers
        if host == "x-callback-url" {
            return pathComponents.first
        }

        if let host, !host.isEmpty {
            return host
        }

        return pathComponents.first
    }

    private static func queryDictionary(from components: URLComponents) -> [String: String] {
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            query[item.name.lowercased()] = value
        }
        return query
    }

    private static func parseGroupTarget(from query: [String: String]) -> URLGroupTarget? {
        if let idText = query["groupid"] ?? query["id"],
           let uuid = UUID(uuidString: idText) {
            return .id(uuid)
        }

        if let indexText = query["index"] ?? query["groupindex"],
           let index = Int(indexText), index > 0 {
            return .index(index)
        }

        if let rawName = query["group"] ?? query["name"] {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return .name(name)
            }
        }

        return nil
    }

    private static func parseSettingsTab(from query: [String: String]) -> URLSettingsTab? {
        guard let rawTab = query["tab"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawTab.isEmpty else {
            return nil
        }

        switch rawTab {
        case "groups", "group":
            return .groups
        case "general", "app", "application":
            return .general
        default:
            return nil
        }
    }

    private static func shouldOpenBackupBrowser(from query: [String: String]) -> Bool {
        let candidates = [
            query["tab"],
            query["section"],
            query["panel"],
            query["view"]
        ]
        let value = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first(where: { !$0.isEmpty })

        guard let value else { return false }
        return value == "backup" ||
               value == "backups" ||
               value == "backup-browser" ||
               value == "automatic-backups"
    }

    private static func parsePathValue(from query: [String: String]) -> String? {
        let raw = query["path"] ?? query["file"]
        guard let raw else { return nil }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func parseBackupTarget(from query: [String: String]) -> URLBackupTarget? {
        if let path = parsePathValue(from: query) {
            return .path(path)
        }

        if let rawName = query["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawName.isEmpty {
            return .name(rawName)
        }

        if let rawIndex = query["index"] ?? query["backupindex"],
           let index = Int(rawIndex), index > 0 {
            return .index(index)
        }

        // nil => latest backup
        return nil
    }
}

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
        }
    }

    private static func openSettingsWindow(tab: URLSettingsTab?) {
        if let tab {
            ShortcutCycleURLNavigationState.request(tab: tab)
        }

        if let settingsWindow = NSApp.windows.first(where: { window in
            window.title == "Shortcut Cycle" && window.styleMask.contains(.titled)
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

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: Notification.Name("ToggleSettingsWindow"), object: nil)
    }

    private static func openBackupBrowser() {
        ShortcutCycleURLNavigationState.requestBackupBrowser()
        openSettingsWindow(tab: .general)
        NotificationCenter.default.post(name: .backupBrowserRequested, object: nil)
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


class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Run as a menu bar app (no dock icon)
        NSApp.setActivationPolicy(.accessory)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                ShortcutCycleURLRouter.handle(url)
            }
        }
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

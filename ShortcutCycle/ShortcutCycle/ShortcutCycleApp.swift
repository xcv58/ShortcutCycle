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

    private var groupsDisabled: Bool {
        selectedTab != "groups" || GroupStore.shared.groups.count < 2
    }

    var body: some Commands {
        // Keep a non-lazy reference to openWindow for URL/shortcut cold-start requests.
        let _ = SettingsWindowBridge.register(openWindow: openWindow)

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

    class Coordinator {
        private var observer: NSObjectProtocol?
        private weak var observedWindow: NSWindow?

        func observe(window: NSWindow) {
            guard observedWindow !== window else { return }
            observedWindow = window

            window.identifier = NSUserInterfaceItemIdentifier("settings")

            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
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

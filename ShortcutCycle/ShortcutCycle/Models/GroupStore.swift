import Foundation
import SwiftUI
import Combine

public enum ManualBackupResult {
    case saved, noChange, error(String)
}

/// Observable store for managing app groups with persistence
@MainActor
public class GroupStore: ObservableObject {
    public static let shared = GroupStore()
    
    @Published public var groups: [AppGroup] = []
    @Published public var selectedGroupId: UUID?
    @Published public var isAddingGroup = false
    @Published public var columnVisibility: NavigationSplitViewVisibility = .all
    
    private let saveKey = "ShortcutCycle.Groups"
    private let userDefaults: UserDefaults

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter
    }()
    
    // Debounce timer for auto-backup (60 seconds)
    private var backupTimer: Timer?
    private var backupPending = false
    private let backupDebounceInterval: TimeInterval
    private var lastBackupTime: Date = .distantPast

    // Internal init for testing
    init(userDefaults: UserDefaults = .standard, backupDebounceInterval: TimeInterval = 60.0) {
        self.userDefaults = userDefaults
        self.backupDebounceInterval = backupDebounceInterval
        loadGroups()
        setupTerminationObserver()
    }
    
    /// Setup observer to backup when app terminates
    private func setupTerminationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Must run synchronously on main thread before app exits
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.flushPendingBackup()
            }
        }
    }

    /// Force immediate backup if one is pending (public for testing)
    public func flushPendingBackup() {
        guard backupPending else { return }
        backupTimer?.invalidate()
        backupTimer = nil
        performAutoBackup()
    }
    
    public var selectedGroup: AppGroup? {
        get {
            groups.first { $0.id == selectedGroupId }
        }
        set {
            if let newValue = newValue,
               let index = groups.firstIndex(where: { $0.id == newValue.id }) {
                groups[index] = newValue
                saveGroups()
            }
        }
    }
    
    // MARK: - CRUD Operations
    
    public func addGroup(name: String) -> AppGroup {
        let group = AppGroup(name: name)
        groups.append(group)
        selectedGroupId = group.id
        saveGroups()
        return group
    }
    
    public func deleteGroup(_ group: AppGroup) {
        groups.removeAll { $0.id == group.id }
        if selectedGroupId == group.id {
            selectedGroupId = groups.first?.id
        }
        saveGroups()
        
        // Update shortcuts immediately
        NotificationCenter.default.post(name: .shortcutsNeedUpdate, object: nil)
    }
    
    public func updateGroup(_ group: AppGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            // Prevent redundant saves if group hasn't changed
            if groups[index] != group {
                groups[index] = group
                saveGroups()
            }
        }
    }
    
    public func moveGroups(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        saveGroups()
    }
    
    // MARK: - App Management
    
    public func addApp(_ app: AppItem, to groupId: UUID) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].addApp(app)
            saveGroups()
        }
    }
    
    public func removeApp(_ app: AppItem, from groupId: UUID) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].removeApp(app)
            saveGroups()
        }
    }
    
    public func moveApp(in groupId: UUID, from source: IndexSet, to destination: Int) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].moveApp(from: source, to: destination)
            saveGroups()
        }
    }
    
    // MARK: - Shortcut Management
    
    public func updateLastActiveApp(bundleId: String, for groupId: UUID) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].lastActiveAppBundleId = bundleId
            saveGroups()
        }
    }

    public func updateMRUOrder(activatedBundleId: String, for groupId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        let validBundleIds = Set(groups[index].apps.map { $0.bundleIdentifier })
        let newOrder = AppCyclingLogic.updatedMRUOrder(
            currentOrder: groups[index].mruOrder,
            activatedBundleId: activatedBundleId,
            validBundleIds: validBundleIds
        )
        if groups[index].mruOrder != newOrder {
            groups[index].mruOrder = newOrder
            saveGroups()
        }
    }

    // MARK: - Persistence
    
    private func saveGroups() {
        // JSONEncoder.encode cannot fail for [AppGroup] since all types are trivially Codable
        let data = try! JSONEncoder().encode(groups)
        userDefaults.set(data, forKey: saveKey)
        scheduleAutoBackup()
    }

    /// Schedule a debounced auto-backup (resets timer on each call)
    private func scheduleAutoBackup() {
        backupPending = true
        
        // Immediate save if enough time has passed since last backup and no debounce is active
        // This ensures the first change saves immediately, but subsequent rapid changes are debounced
        let timeSinceLastBackup = Date().timeIntervalSince(lastBackupTime)
        if backupTimer == nil && timeSinceLastBackup > backupDebounceInterval {
            performAutoBackup()
            return
        }
        
        // Cancel any existing timer
        backupTimer?.invalidate()
        backupTimer = nil
        
        // Schedule new backup after debounce interval on main run loop
        backupTimer = Timer(timeInterval: backupDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performAutoBackup()
                self?.backupTimer = nil
            }
        }
        RunLoop.main.add(backupTimer!, forMode: .common)
    }
    
    /// Actually write the backup file to disk
    private func performAutoBackup() {
        backupPending = false
        lastBackupTime = Date()

        guard let data = try? exportData() else { return }

        // Skip backup if content is identical to the most recent backup
        if let latestBackup = mostRecentBackupData(), contentEqual(data, latestBackup) {
            return
        }

        let timestamp = Self.backupDateFormatter.string(from: Date())
        let backupFile = backupDirectory.appendingPathComponent("backup \(timestamp).json")
        try? data.write(to: backupFile, options: .atomic)

        cleanupOldBackups(in: backupDirectory)
    }

    /// Returns the Data contents of the most recent backup file, if any
    private func mostRecentBackupData() -> Data? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey]) else { return nil }
        let latest = files
            .filter { $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json" }
            .compactMap { url -> (URL, Date)? in
                guard let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate else { return nil }
                return (url, date)
            }
            .max(by: { $0.1 < $1.1 })
        guard let latestURL = latest?.0 else { return nil }
        return try? Data(contentsOf: latestURL)
    }
    
    /// Directory where backups are stored
    public var backupDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dirName = userDefaults == .standard ? "ShortcutCycle" : "ShortcutCycle-Test"
        let url = appSupport.appendingPathComponent(dirName, isDirectory: true)
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        
        return url
    }

    /// Thin old backups using GFS (Grandfather-Father-Son) retention policy.
    /// Keeps more granularity for recent backups, progressively fewer for older ones.
    private func cleanupOldBackups(in directory: URL) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let backupFiles = files
            .filter { $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json" }
            .map { url -> BackupRetention.TimedFile in
                var date = Date.distantPast
                if let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate {
                    date = creationDate
                }
                return BackupRetention.TimedFile(url: url, date: date)
            }

        for url in BackupRetention.filesToDelete(from: backupFiles) {
            try? fileManager.removeItem(at: url)
        }
    }
    
    private func loadGroups() {
        guard let data = userDefaults.data(forKey: saveKey) else {
            // Create default groups on first launch
            createDefaultGroups()
            return
        }
        
        do {
            groups = try JSONDecoder().decode([AppGroup].self, from: data)
            selectedGroupId = groups.first?.id
        } catch {
            print("Failed to load groups: \(error)")
            createDefaultGroups()
        }
    }
    
    private func createDefaultGroups() {
        let browsersGroup = AppGroup(name: "Browsers", apps: [])
        let chatGroup = AppGroup(name: "Chat", apps: [])
        
        groups = [browsersGroup, chatGroup]
        selectedGroupId = browsersGroup.id
        saveGroups()
    }
    
    // MARK: - Manual Backup

    public func manualBackup() -> ManualBackupResult {
        // exportData() uses JSONEncoder on trivially Codable types, cannot fail
        guard let data = try? exportData() else { return .error("Export failed") }

        if let latestBackup = mostRecentBackupData(),
           contentEqual(data, latestBackup) {
            return .noChange
        }

        let timestamp = Self.backupDateFormatter.string(from: Date())
        let backupFile = backupDirectory.appendingPathComponent("backup \(timestamp).json")
        try? data.write(to: backupFile, options: .atomic)
        cleanupOldBackups(in: backupDirectory)
        return .saved
    }

    /// Compare two export payloads ignoring the exportDate field
    private func contentEqual(_ a: Data, _ b: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let ea = try? decoder.decode(SettingsExport.self, from: a),
              let eb = try? decoder.decode(SettingsExport.self, from: b) else {
            return a == b
        }
        return ea.groups == eb.groups &&
               ea.settings == eb.settings &&
               ea.shortcuts == eb.shortcuts
    }

    // MARK: - Export/Import
    
    /// Export all settings as JSON data
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let exportPayload = SettingsExport.fullSnapshot(groups: groups)
        return try encoder.encode(exportPayload)
    }

    /// Import settings from exported JSON data
    public func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let importPayload = try decoder.decode(SettingsExport.self, from: data)
        applyImport(importPayload)
    }

    /// Apply a decoded settings export directly
    public func applyImport(_ payload: SettingsExport) {
        self.groups = payload.groups
        self.selectedGroupId = groups.first?.id
        saveGroups()

        // Apply app settings if present (version 2+)
        payload.settings?.apply()

        // Apply keyboard shortcuts if present (version 3+)
        payload.applyShortcuts()

        // Re-register shortcuts for new groups
        NotificationCenter.default.post(name: .shortcutsNeedUpdate, object: nil)
    }
    
    // MARK: - Group Actions
    
    public func toggleGroupEnabled(_ group: AppGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index].isEnabled.toggle()
            saveGroups()
            NotificationCenter.default.post(name: .shortcutsNeedUpdate, object: nil)
        }
    }
    
    public func renameGroup(_ group: AppGroup, newName: String) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index].name = newName
            groups[index].lastModified = Date()
            saveGroups()
        }
    }
    
}

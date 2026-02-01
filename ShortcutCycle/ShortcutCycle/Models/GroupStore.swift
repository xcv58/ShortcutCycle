import Foundation
import SwiftUI

/// Observable store for managing app groups with persistence
@MainActor
public class GroupStore: ObservableObject {
    public static let shared = GroupStore()
    
    @Published public var groups: [AppGroup] = []
    @Published public var selectedGroupId: UUID?
    
    private let saveKey = "ShortcutCycle.Groups"
    private let userDefaults: UserDefaults
    
    // Debounce timer for auto-backup (60 seconds)
    private var backupTimer: Timer?
    private var backupPending = false
    private let backupDebounceInterval: TimeInterval = 60.0
    private var lastBackupTime: Date = .distantPast
    
    // Internal init for testing
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
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
    
    // MARK: - Persistence
    
    private func saveGroups() {
        do {
            let data = try JSONEncoder().encode(groups)
            userDefaults.set(data, forKey: saveKey)
            scheduleAutoBackup()
        } catch {
            print("GroupStore: Failed to save groups: \(error)")
        }
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
        
        do {
            let data = try exportData()
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
            let timestamp = dateFormatter.string(from: Date())
            let backupFile = backupDirectory.appendingPathComponent("backup \(timestamp).json")
            try data.write(to: backupFile, options: .atomic)
            
            // Cleanup: keep only the 100 most recent backups
            cleanupOldBackups(in: backupDirectory, keeping: 100)
        } catch {
            print("GroupStore: Auto-backup failed: \(error)")
        }
    }
    
    /// Directory where backups are stored
    private var backupDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dirName = userDefaults == .standard ? "ShortcutCycle" : "ShortcutCycle-Test"
        let url = appSupport.appendingPathComponent(dirName, isDirectory: true)
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        
        return url
    }
    


    
    /// Remove old backup files, keeping only the specified number of most recent ones
    private func cleanupOldBackups(in directory: URL, keeping maxCount: Int) {
        do {
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            let backupFiles = files.filter { $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json" }
            
            guard backupFiles.count > maxCount else { return }
            
            // Sort by creation date in descending order (newest first)
            let sortedFiles = backupFiles.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return date1 > date2
            }
            
            // Delete files beyond the max count
            let filesToDelete = sortedFiles.dropFirst(maxCount)
            for file in filesToDelete {
                try fileManager.removeItem(at: file)
            }
        } catch {
            print("GroupStore: Backup cleanup failed: \(error)")
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

        // Replace all groups with imported data
        self.groups = importPayload.groups
        self.selectedGroupId = groups.first?.id
        saveGroups()

        // Apply app settings if present (version 2+)
        importPayload.settings?.apply()

        // Apply keyboard shortcuts if present (version 3+)
        importPayload.applyShortcuts()

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

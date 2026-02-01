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
    
    // Internal init for testing
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadGroups()
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
            groups[index] = group
            saveGroups()
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
            autoBackup()
        } catch {
            print("GroupStore: Failed to save groups: \(error)")
        }
    }

    /// Write a full settings backup to Application Support
    private func autoBackup() {
        do {
            let data = try exportData()
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let backupDir = appSupport.appendingPathComponent("ShortcutCycle", isDirectory: true)
            try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let backupFile = backupDir.appendingPathComponent("backup.json")
            try data.write(to: backupFile, options: .atomic)
        } catch {
            print("GroupStore: Auto-backup failed: \(error)")
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

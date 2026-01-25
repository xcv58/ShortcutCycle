import Foundation
import SwiftUI

/// Observable store for managing app groups with persistence
@MainActor
class GroupStore: ObservableObject {
    @Published var groups: [AppGroup] = []
    @Published var selectedGroupId: UUID?
    
    private let saveKey = "ShortcutCycle.Groups"
    
    init() {
        loadGroups()
    }
    
    var selectedGroup: AppGroup? {
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
    
    func addGroup(name: String) -> AppGroup {
        let group = AppGroup(name: name)
        groups.append(group)
        selectedGroupId = group.id
        saveGroups()
        return group
    }
    
    func deleteGroup(_ group: AppGroup) {
        groups.removeAll { $0.id == group.id }
        if selectedGroupId == group.id {
            selectedGroupId = groups.first?.id
        }
        saveGroups()
    }
    
    func updateGroup(_ group: AppGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
            saveGroups()
        }
    }
    
    func moveGroups(from source: IndexSet, to destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        saveGroups()
    }
    
    // MARK: - App Management
    
    func addApp(_ app: AppItem, to groupId: UUID) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].addApp(app)
            saveGroups()
        }
    }
    
    func removeApp(_ app: AppItem, from groupId: UUID) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].removeApp(app)
            saveGroups()
        }
    }
    
    func moveApp(in groupId: UUID, from source: IndexSet, to destination: Int) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].moveApp(from: source, to: destination)
            saveGroups()
        }
    }
    
    // MARK: - Shortcut Management
    
    func setShortcut(_ shortcut: KeyboardShortcutData?, for groupId: UUID) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].shortcut = shortcut
            saveGroups()
        }
    }
    
    func updateLastActiveApp(bundleId: String, for groupId: UUID) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].lastActiveAppBundleId = bundleId
            saveGroups()
        }
    }
    
    // MARK: - Persistence
    
    private func saveGroups() {
        do {
            let data = try JSONEncoder().encode(groups)
            UserDefaults.standard.set(data, forKey: saveKey)
            // notifyCloudSync() // Temporarily disabled
        } catch {
            print("Failed to save groups: \(error)")
        }
    }
    
    private func loadGroups() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else {
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
    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let exportPayload = SettingsExport(groups: groups, settings: AppSettings.current())
        return try encoder.encode(exportPayload)
    }
    
    /// Import settings from exported JSON data
    func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let importPayload = try decoder.decode(SettingsExport.self, from: data)
        
        // Replace all groups with imported data
        self.groups = importPayload.groups
        self.selectedGroupId = groups.first?.id
        saveGroups()
        
        // Apply app settings if present (version 2+)
        importPayload.settings?.apply()
        
        // Re-register shortcuts for new groups
        ShortcutManager.shared.registerAllShortcuts()
    }
    
    // MARK: - Group Actions
    
    func toggleGroupEnabled(_ group: AppGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index].isEnabled.toggle()
            saveGroups()
            ShortcutManager.shared.registerAllShortcuts()
        }
    }
    
    func renameGroup(_ group: AppGroup, newName: String) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index].name = newName
            groups[index].lastModified = Date()
            saveGroups()
        }
    }
    
    // MARK: - Cloud Sync Support
    
    /// Replace all groups with synced data (used by CloudSyncManager)
    func replaceAllGroups(_ newGroups: [AppGroup]) {
        self.groups = newGroups
        self.selectedGroupId = groups.first?.id
        saveGroups()
        ShortcutManager.shared.registerAllShortcuts()
    }
    
    /* Temporarily disabled - iCloud sync
    /// Notify cloud sync of local changes
    func notifyCloudSync() {
        if CloudSyncManager.shared.isSyncEnabled {
            CloudSyncManager.shared.pushToCloud()
        }
    }
    */
    
    // Stub for when iCloud is disabled
    func notifyCloudSync() { }
}

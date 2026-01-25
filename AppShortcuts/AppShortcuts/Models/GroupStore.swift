import Foundation
import SwiftUI

/// Observable store for managing app groups with persistence
@MainActor
class GroupStore: ObservableObject {
    @Published var groups: [AppGroup] = []
    @Published var selectedGroupId: UUID?
    
    private let saveKey = "AppShortcuts.Groups"
    
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
        let editorGroup = AppGroup(name: "Editors", apps: [])
        let browserGroup = AppGroup(name: "Browsers", apps: [])
        groups = [editorGroup, browserGroup]
        selectedGroupId = editorGroup.id
        saveGroups()
    }
}

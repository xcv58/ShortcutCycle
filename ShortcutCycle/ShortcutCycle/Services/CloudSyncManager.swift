import Foundation
import Combine

/// Manages iCloud key-value sync for settings
@MainActor
class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()
    
    // MARK: - Published State
    @Published var isSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: syncEnabledKey)
            if isSyncEnabled {
                startSync()
            } else {
                stopSync()
            }
        }
    }
    @Published var lastSyncDate: Date?
    @Published var isSyncing: Bool = false
    @Published var syncError: String?
    
    // MARK: - Private Properties
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let cloudKey = "ShortcutCycle.Groups"
    private let lastSyncKey = "ShortcutCycle.LastSync"
    private let syncEnabledKey = "ShortcutCycle.iCloudSyncEnabled"
    private var observer: NSObjectProtocol?
    private weak var groupStore: GroupStore?
    
    // MARK: - Initialization
    
    private init() {
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: syncEnabledKey)
        self.lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
        
        if isSyncEnabled {
            startSync()
        }
    }
    
    // deinit removed as CloudSyncManager is a singleton and deinit logic caused concurrency issues.
    // original deinit called stopSync() which is MainActor-isolated.
    
    // MARK: - Public Methods
    
    func setGroupStore(_ store: GroupStore) {
        self.groupStore = store
    }
    
    /// Start listening for iCloud changes and sync
    func startSync() {
        guard observer == nil else { return }
        
        // Listen for external changes from iCloud
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleExternalChange(notification)
            }
        }
        
        // Synchronize to get latest from iCloud
        cloudStore.synchronize()
        
        // Pull any existing cloud data
        pullFromCloud()
    }
    
    /// Stop listening for iCloud changes
    func stopSync() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
    
    /// Push local changes to iCloud
    func pushToCloud() {
        guard isSyncEnabled, let store = groupStore else { return }
        
        isSyncing = true
        syncError = nil
        
        do {
            let payload = SyncPayload(groups: store.groups)
            let data = try JSONEncoder().encode(payload)
            
            cloudStore.set(data, forKey: cloudKey)
            cloudStore.synchronize()
            
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
            
            isSyncing = false
        } catch {
            syncError = "Failed to push: \(error.localizedDescription)"
            isSyncing = false
        }
    }
    
    /// Pull changes from iCloud and merge
    func pullFromCloud() {
        guard isSyncEnabled, let store = groupStore else { return }
        
        isSyncing = true
        syncError = nil
        
        guard let data = cloudStore.data(forKey: cloudKey) else {
            // No cloud data yet, push local data
            isSyncing = false
            pushToCloud()
            return
        }
        
        do {
            let payload = try JSONDecoder().decode(SyncPayload.self, from: data)
            let mergedGroups = mergeGroups(local: store.groups, remote: payload.groups)
            
            // Update local store with merged data
            store.replaceAllGroups(mergedGroups)
            
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
            
            // Push merged result back to ensure consistency
            pushToCloud()
            
            isSyncing = false
        } catch {
            syncError = "Failed to pull: \(error.localizedDescription)"
            isSyncing = false
        }
    }
    
    /// Force sync now
    func syncNow() {
        pullFromCloud()
    }
    
    // MARK: - Private Methods
    
    private func handleExternalChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }
        
        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // New data from iCloud, pull and merge
            pullFromCloud()
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            syncError = "iCloud storage quota exceeded"
        case NSUbiquitousKeyValueStoreAccountChange:
            // iCloud account changed, re-sync
            pullFromCloud()
        default:
            break
        }
    }
    
    /// Merge local and remote groups using per-group timestamps
    private func mergeGroups(local: [AppGroup], remote: [AppGroup]) -> [AppGroup] {
        var result: [AppGroup] = []
        var processedIds: Set<UUID> = []
        
        // Process all local groups
        for localGroup in local {
            processedIds.insert(localGroup.id)
            
            if let remoteGroup = remote.first(where: { $0.id == localGroup.id }) {
                // Group exists in both - keep the newer one
                if remoteGroup.lastModified > localGroup.lastModified {
                    result.append(remoteGroup)
                } else {
                    result.append(localGroup)
                }
            } else {
                // Only exists locally - keep it
                result.append(localGroup)
            }
        }
        
        // Add groups that only exist remotely
        for remoteGroup in remote where !processedIds.contains(remoteGroup.id) {
            result.append(remoteGroup)
        }
        
        return result
    }
}

// MARK: - Sync Payload

/// Wrapper for iCloud sync data
private struct SyncPayload: Codable {
    let groups: [AppGroup]
    let syncDate: Date
    
    init(groups: [AppGroup]) {
        self.groups = groups
        self.syncDate = Date()
    }
}

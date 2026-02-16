import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

@MainActor
final class GroupStoreTests: XCTestCase {

    var userDefaults: UserDefaults!
    var store: GroupStore!

    override func setUp() {
        super.setUp()
        // Use a clean suite specifically for tests
        userDefaults = UserDefaults(suiteName: "TestDefaults")
        userDefaults.removePersistentDomain(forName: "TestDefaults")
        store = GroupStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        // Clean up backup directory
        let fm = FileManager.default
        try? fm.removeItem(at: store.backupDirectory)
        userDefaults.removePersistentDomain(forName: "TestDefaults")
        store = nil
        userDefaults = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        // Defaults should be created
        XCTAssertEqual(store.groups.count, 2)
        XCTAssertEqual(store.groups.first?.name, "Browsers")
    }

    func testInitialSelectedGroupIsFirst() {
        XCTAssertEqual(store.selectedGroupId, store.groups.first?.id)
    }

    // MARK: - Add Group

    func testAddGroup() {
        let count = store.groups.count
        let newGroup = store.addGroup(name: "New Group")

        XCTAssertEqual(store.groups.count, count + 1)
        XCTAssertEqual(newGroup.name, "New Group")
        XCTAssertEqual(store.selectedGroupId, newGroup.id)
    }

    func testAddGroupSelectsNewGroup() {
        let group1 = store.addGroup(name: "First")
        XCTAssertEqual(store.selectedGroupId, group1.id)
        let group2 = store.addGroup(name: "Second")
        XCTAssertEqual(store.selectedGroupId, group2.id)
    }

    // MARK: - Delete Group

    func testDeleteGroup() {
        let group = store.groups.first!
        store.deleteGroup(group)

        XCTAssertFalse(store.groups.contains(where: { $0.id == group.id }))
    }

    func testDeleteSelectedGroupSelectsFirst() {
        let group = store.addGroup(name: "To Delete")
        XCTAssertEqual(store.selectedGroupId, group.id)

        store.deleteGroup(group)

        // Should fall back to first group
        XCTAssertEqual(store.selectedGroupId, store.groups.first?.id)
    }

    func testDeleteNonSelectedGroupKeepsSelection() {
        let first = store.groups.first!
        let added = store.addGroup(name: "Added")
        // Selection is now on 'added'
        XCTAssertEqual(store.selectedGroupId, added.id)

        // Delete the first group (not selected)
        store.deleteGroup(first)

        // Selection should remain on 'added'
        XCTAssertEqual(store.selectedGroupId, added.id)
    }

    func testDeleteAllGroupsResultsInNilSelection() {
        while let group = store.groups.first {
            store.deleteGroup(group)
        }

        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertNil(store.selectedGroupId)
    }

    // MARK: - Update Group

    func testUpdateGroup() {
        var group = store.groups.first!
        group.name = "Updated Name"

        store.updateGroup(group)

        XCTAssertEqual(store.groups.first?.name, "Updated Name")
    }

    func testUpdateGroupNoOpWhenUnchanged() {
        let group = store.groups.first!
        store.updateGroup(group)
        XCTAssertEqual(store.groups.first?.name, group.name)
    }

    func testUpdateNonexistentGroupIsNoOp() {
        let phantom = AppGroup(name: "Phantom")
        let countBefore = store.groups.count
        store.updateGroup(phantom)
        XCTAssertEqual(store.groups.count, countBefore)
    }

    // MARK: - Move Groups

    func testMoveGroupsReorders() {
        let _ = store.addGroup(name: "Third")
        // Groups: Browsers, Chat, Third
        let originalFirst = store.groups[0].name

        store.moveGroups(from: IndexSet(integer: 0), to: 3)
        // Groups: Chat, Third, Browsers

        XCTAssertEqual(store.groups.last?.name, originalFirst)
    }

    // MARK: - App Management

    func testAddAppToGroup() {
        let groupId = store.groups.first!.id
        let app = AppItem(bundleIdentifier: "com.test.app", name: "Test App")

        store.addApp(app, to: groupId)

        let group = store.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group?.apps.count, 1)
        XCTAssertEqual(group?.apps.first?.bundleIdentifier, "com.test.app")
    }

    func testAddDuplicateAppToGroup() {
        let groupId = store.groups.first!.id
        let app = AppItem(bundleIdentifier: "com.test.app", name: "Test App")

        store.addApp(app, to: groupId)
        store.addApp(app, to: groupId)

        let group = store.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group?.apps.count, 1)
    }

    func testAddAppToNonexistentGroup() {
        let app = AppItem(bundleIdentifier: "com.test.app", name: "Test App")
        let countBefore = store.groups.flatMap(\.apps).count

        store.addApp(app, to: UUID())

        let countAfter = store.groups.flatMap(\.apps).count
        XCTAssertEqual(countBefore, countAfter)
    }

    func testRemoveAppFromGroup() {
        let groupId = store.groups.first!.id
        let app = AppItem(bundleIdentifier: "com.test.app", name: "Test App")

        store.addApp(app, to: groupId)
        store.removeApp(app, from: groupId)

        let group = store.groups.first(where: { $0.id == groupId })
        XCTAssertTrue(group?.apps.isEmpty ?? false)
    }

    func testMoveAppInGroup() {
        let groupId = store.groups.first!.id
        let app1 = AppItem(bundleIdentifier: "com.test.1", name: "App 1")
        let app2 = AppItem(bundleIdentifier: "com.test.2", name: "App 2")
        let app3 = AppItem(bundleIdentifier: "com.test.3", name: "App 3")

        store.addApp(app1, to: groupId)
        store.addApp(app2, to: groupId)
        store.addApp(app3, to: groupId)

        // Move first to end
        store.moveApp(in: groupId, from: IndexSet(integer: 0), to: 3)

        let group = store.groups.first(where: { $0.id == groupId })!
        XCTAssertEqual(group.apps[0].bundleIdentifier, "com.test.2")
        XCTAssertEqual(group.apps[1].bundleIdentifier, "com.test.3")
        XCTAssertEqual(group.apps[2].bundleIdentifier, "com.test.1")
    }

    // MARK: - Last Active App

    func testUpdateLastActiveApp() {
        let groupId = store.groups.first!.id

        store.updateLastActiveApp(bundleId: "com.active.app", for: groupId)

        let group = store.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group?.lastActiveAppBundleId, "com.active.app")
    }

    func testUpdateLastActiveAppOverwritesPrevious() {
        let groupId = store.groups.first!.id

        store.updateLastActiveApp(bundleId: "com.first.app", for: groupId)
        store.updateLastActiveApp(bundleId: "com.second.app", for: groupId)

        let group = store.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group?.lastActiveAppBundleId, "com.second.app")
    }

    func testUpdateLastActiveAppNonexistentGroup() {
        // Should not crash
        store.updateLastActiveApp(bundleId: "com.test.app", for: UUID())
    }

    // MARK: - Toggle Group Enabled

    func testToggleGroupEnabled() {
        let group = store.groups.first!
        XCTAssertTrue(group.isEnabled)

        store.toggleGroupEnabled(group)

        let updated = store.groups.first(where: { $0.id == group.id })
        XCTAssertFalse(updated?.isEnabled ?? true)
    }

    func testToggleGroupEnabledTwiceRestoresState() {
        let group = store.groups.first!

        store.toggleGroupEnabled(group)
        store.toggleGroupEnabled(store.groups.first(where: { $0.id == group.id })!)

        let updated = store.groups.first(where: { $0.id == group.id })
        XCTAssertTrue(updated?.isEnabled ?? false)
    }

    // MARK: - Rename Group

    func testRenameGroup() {
        let group = store.groups.first!
        let oldModified = group.lastModified

        store.renameGroup(group, newName: "Renamed")

        let updated = store.groups.first(where: { $0.id == group.id })
        XCTAssertEqual(updated?.name, "Renamed")
        XCTAssertGreaterThanOrEqual(updated?.lastModified ?? .distantPast, oldModified)
    }

    // MARK: - Selected Group Property

    func testSelectedGroupGetter() {
        let group = store.groups.first!
        store.selectedGroupId = group.id

        XCTAssertEqual(store.selectedGroup?.id, group.id)
    }

    func testSelectedGroupSetterUpdatesGroup() {
        var group = store.groups.first!
        store.selectedGroupId = group.id
        group.name = "Via Setter"

        store.selectedGroup = group

        XCTAssertEqual(store.groups.first?.name, "Via Setter")
    }

    // MARK: - Export/Import Round-Trip

    func testExportImportRoundTrip() throws {
        let _ = store.addGroup(name: "Export Test")
        let app = AppItem(bundleIdentifier: "com.export.app", name: "Export App")
        store.addApp(app, to: store.groups.last!.id)

        let data = try store.exportData()

        // Create a fresh store and import
        let freshDefaults = UserDefaults(suiteName: "TestImport")!
        freshDefaults.removePersistentDomain(forName: "TestImport")
        let freshStore = GroupStore(userDefaults: freshDefaults)

        try freshStore.importData(data)

        XCTAssertTrue(freshStore.groups.contains(where: { $0.name == "Export Test" }))
        let importedGroup = freshStore.groups.first(where: { $0.name == "Export Test" })
        XCTAssertEqual(importedGroup?.apps.first?.bundleIdentifier, "com.export.app")

        // Cleanup
        try? FileManager.default.removeItem(at: freshStore.backupDirectory)
        freshDefaults.removePersistentDomain(forName: "TestImport")
    }

    func testImportMalformedDataThrows() {
        let badData = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try store.importData(badData))
    }

    func testImportReplacesExistingGroups() throws {
        let newGroup = AppGroup(name: "Imported")
        let export = SettingsExport(groups: [newGroup])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)

        try store.importData(data)

        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups.first?.name, "Imported")
    }

    // MARK: - Persistence

    func testGroupsPersistAcrossStoreInstances() {
        _ = store.addGroup(name: "Persistent")

        // Create new store with same defaults
        let store2 = GroupStore(userDefaults: userDefaults)
        XCTAssertTrue(store2.groups.contains(where: { $0.name == "Persistent" }))
    }

    // MARK: - Manual Backup Tests

    func testManualBackupSavesFile() {
        _ = store.addGroup(name: "BackupTest")
        let result = store.manualBackup()
        XCTAssertEqual(result, .saved)

        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: store.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []
        XCTAssertGreaterThanOrEqual(files.count, 1)
    }

    func testManualBackupNoChangeSkips() {
        _ = store.addGroup(name: "BackupTest2")
        let first = store.manualBackup()
        XCTAssertEqual(first, .saved)

        let second = store.manualBackup()
        XCTAssertEqual(second, .noChange)
    }

    func testPerformAutoBackupSkipsDuplicate() {
        _ = store.addGroup(name: "AutoBackupTest")
        store.flushPendingBackup()

        let fm = FileManager.default
        let countBefore = ((try? fm.contentsOfDirectory(at: store.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        // Flush again without changes
        store.flushPendingBackup()

        let countAfter = ((try? fm.contentsOfDirectory(at: store.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        XCTAssertEqual(countBefore, countAfter)
    }

    func testPerformAutoBackupSkipsDuplicateContent() {
        // This test exercises the contentEqual path inside performAutoBackup.
        // 1. Ensure a backup exists that matches current state via manual backup
        let result = store.manualBackup()
        XCTAssertTrue(result == .saved || result == .noChange)

        // 2. A no-op move triggers saveGroups/scheduleAutoBackup without changing content
        //    Since lastBackupTime was just set (by setUp's init), it schedules a timer.
        store.moveGroups(from: IndexSet(integer: 0), to: 0)

        let fm = FileManager.default
        let countBefore = ((try? fm.contentsOfDirectory(at: store.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        // 3. Flush → performAutoBackup runs, content matches existing backup → no new file
        store.flushPendingBackup()

        let countAfter = ((try? fm.contentsOfDirectory(at: store.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        XCTAssertEqual(countBefore, countAfter)
    }

    func testManualBackupAfterChangeCreatesNewFile() {
        _ = store.addGroup(name: "Initial")
        let first = store.manualBackup()
        XCTAssertEqual(first, .saved)

        // Make a change
        _ = store.addGroup(name: "Changed")

        // Small delay to ensure different timestamp
        Thread.sleep(forTimeInterval: 1.1)

        let second = store.manualBackup()
        XCTAssertEqual(second, .saved)
    }

    // MARK: - Corrupt Data Recovery

    func testCorruptDataFallsBackToDefaults() {
        // Write corrupt data to the save key
        userDefaults.set("not valid json data".data(using: .utf8), forKey: "ShortcutCycle.Groups")

        // Create a new store — it should recover gracefully with defaults
        let corruptStore = GroupStore(userDefaults: userDefaults)

        XCTAssertEqual(corruptStore.groups.count, 2)
        XCTAssertEqual(corruptStore.groups.first?.name, "Browsers")

        try? FileManager.default.removeItem(at: corruptStore.backupDirectory)
    }

    // MARK: - Apply Import

    func testApplyImportDirectly() {
        let group = AppGroup(name: "Direct Import", apps: [
            AppItem(bundleIdentifier: "com.direct.app", name: "Direct")
        ])
        let payload = SettingsExport(groups: [group])

        store.applyImport(payload)

        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups[0].name, "Direct Import")
        XCTAssertEqual(store.selectedGroupId, store.groups.first?.id)
    }

    func testApplyImportWithSettings() {
        let defaults = UserDefaults.standard
        let originalShowHUD = defaults.object(forKey: "showHUD")
        defer {
            if let v = originalShowHUD { defaults.set(v, forKey: "showHUD") } else { defaults.removeObject(forKey: "showHUD") }
        }

        let settings = AppSettings(showHUD: false, showShortcutInHUD: true)
        let payload = SettingsExport(groups: [AppGroup(name: "G")], settings: settings)

        store.applyImport(payload)

        XCTAssertEqual(defaults.bool(forKey: "showHUD"), false)
    }

    func testApplyImportWithShortcuts() {
        let group = AppGroup(name: "With Shortcuts")
        let shortcuts: [String: ShortcutData] = [
            group.id.uuidString: ShortcutData(carbonKeyCode: 0, carbonModifiers: 256)
        ]
        let payload = SettingsExport(groups: [group], shortcuts: shortcuts)

        // Should not crash
        store.applyImport(payload)

        XCTAssertEqual(store.groups.count, 1)
    }

    // MARK: - Rename Non-existent Group

    func testRenameNonexistentGroupIsNoOp() {
        let phantom = AppGroup(name: "Ghost")
        let countBefore = store.groups.count

        store.renameGroup(phantom, newName: "New Name")

        XCTAssertEqual(store.groups.count, countBefore)
        XCTAssertFalse(store.groups.contains(where: { $0.name == "New Name" }))
    }

    // MARK: - Toggle Non-existent Group

    func testToggleNonexistentGroupIsNoOp() {
        let phantom = AppGroup(name: "Ghost")
        let countBefore = store.groups.count

        store.toggleGroupEnabled(phantom)

        XCTAssertEqual(store.groups.count, countBefore)
    }

    // MARK: - Remove/Move App on Non-existent Group

    func testRemoveAppFromNonexistentGroup() {
        let app = AppItem(bundleIdentifier: "com.test", name: "T")
        // Should not crash
        store.removeApp(app, from: UUID())
    }

    func testMoveAppInNonexistentGroup() {
        // Should not crash
        store.moveApp(in: UUID(), from: IndexSet(integer: 0), to: 1)
    }

    // MARK: - Selected Group Setter with Nil

    func testSelectedGroupSetterWithNonexistentGroup() {
        let phantom = AppGroup(name: "Ghost")
        let originalName = store.groups.first?.name

        store.selectedGroup = phantom

        // Should not modify any existing group
        XCTAssertEqual(store.groups.first?.name, originalName)
    }

    // MARK: - Debounced Auto-Backup

    func testScheduleAutoBackupCreatesBackup() {
        // Adding a group triggers scheduleAutoBackup → immediate first save
        _ = store.addGroup(name: "AutoSave")

        // The first change should trigger an immediate backup (no debounce timer yet)
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: store.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []
        XCTAssertGreaterThanOrEqual(files.count, 1)
    }

    func testMultipleRapidChangesDebounce() {
        // First change triggers immediate backup
        _ = store.addGroup(name: "Rapid1")

        let fm = FileManager.default
        let countAfterFirst = ((try? fm.contentsOfDirectory(at: store.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        // Subsequent rapid changes should be debounced (not create immediate backups)
        _ = store.addGroup(name: "Rapid2")
        _ = store.addGroup(name: "Rapid3")

        let countAfterRapid = ((try? fm.contentsOfDirectory(at: store.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        // Debounce means the count should not increase for each rapid change
        XCTAssertEqual(countAfterRapid, countAfterFirst)

        // But flushing should create the backup
        store.flushPendingBackup()

        let countAfterFlush = ((try? fm.contentsOfDirectory(at: store.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        XCTAssertGreaterThanOrEqual(countAfterFlush, countAfterFirst)
    }

    // MARK: - MRU Order

    func testMRUOrderNilByDefault() {
        let group = store.groups.first!
        XCTAssertNil(group.mruOrder)
    }

    func testUpdateMRUOrder() {
        let groupId = store.groups.first!.id
        let app1 = AppItem(bundleIdentifier: "com.test.1", name: "App 1")
        let app2 = AppItem(bundleIdentifier: "com.test.2", name: "App 2")
        store.addApp(app1, to: groupId)
        store.addApp(app2, to: groupId)

        store.updateMRUOrder(activatedId: "com.test.2", activatedBundleId: "com.test.2", for: groupId, liveItemIds: Set(["com.test.1", "com.test.2"]))

        let group = store.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group?.mruOrder, ["com.test.2"])
    }

    func testUpdateMRUOrderMovesToFront() {
        let groupId = store.groups.first!.id
        let app1 = AppItem(bundleIdentifier: "com.test.1", name: "App 1")
        let app2 = AppItem(bundleIdentifier: "com.test.2", name: "App 2")
        let app3 = AppItem(bundleIdentifier: "com.test.3", name: "App 3")
        store.addApp(app1, to: groupId)
        store.addApp(app2, to: groupId)
        store.addApp(app3, to: groupId)

        let liveIds: Set<String> = ["com.test.1", "com.test.2", "com.test.3"]
        store.updateMRUOrder(activatedId: "com.test.1", activatedBundleId: "com.test.1", for: groupId, liveItemIds: liveIds)
        store.updateMRUOrder(activatedId: "com.test.3", activatedBundleId: "com.test.3", for: groupId, liveItemIds: liveIds)
        store.updateMRUOrder(activatedId: "com.test.1", activatedBundleId: "com.test.1", for: groupId, liveItemIds: liveIds)

        let group = store.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group?.mruOrder, ["com.test.1", "com.test.3"])
    }

    func testUpdateMRUOrderFiltersStale() {
        let groupId = store.groups.first!.id
        let app1 = AppItem(bundleIdentifier: "com.test.1", name: "App 1")
        let app2 = AppItem(bundleIdentifier: "com.test.2", name: "App 2")
        store.addApp(app1, to: groupId)
        store.addApp(app2, to: groupId)

        store.updateMRUOrder(activatedId: "com.test.1", activatedBundleId: "com.test.1", for: groupId, liveItemIds: Set(["com.test.1", "com.test.2"]))
        store.updateMRUOrder(activatedId: "com.test.2", activatedBundleId: "com.test.2", for: groupId, liveItemIds: Set(["com.test.1", "com.test.2"]))

        // Remove app1 from the group
        store.removeApp(app1, from: groupId)

        // Update MRU — com.test.1 should be filtered out (not in valid bundle IDs, not live)
        store.updateMRUOrder(activatedId: "com.test.2", activatedBundleId: "com.test.2", for: groupId, liveItemIds: Set(["com.test.2"]))

        let group = store.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group?.mruOrder, ["com.test.2"])
    }

    func testUpdateMRUOrderPersistsAcrossInstances() {
        let groupId = store.groups.first!.id
        let app = AppItem(bundleIdentifier: "com.test.1", name: "App 1")
        store.addApp(app, to: groupId)
        store.updateMRUOrder(activatedId: "com.test.1", activatedBundleId: "com.test.1", for: groupId, liveItemIds: Set(["com.test.1"]))

        let store2 = GroupStore(userDefaults: userDefaults)
        let group = store2.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group?.mruOrder, ["com.test.1"])
    }

    func testUpdateMRUOrderNonexistentGroup() {
        // Should not crash
        store.updateMRUOrder(activatedId: "com.test", activatedBundleId: "com.test", for: UUID(), liveItemIds: Set(["com.test"]))
    }

    func testExportImportPreservesMRUOrder() throws {
        let groupId = store.groups.first!.id
        let app = AppItem(bundleIdentifier: "com.test.1", name: "App 1")
        store.addApp(app, to: groupId)
        store.updateMRUOrder(activatedId: "com.test.1", activatedBundleId: "com.test.1", for: groupId, liveItemIds: Set(["com.test.1"]))

        let data = try store.exportData()

        let freshDefaults = UserDefaults(suiteName: "TestMRUExport")!
        freshDefaults.removePersistentDomain(forName: "TestMRUExport")
        let freshStore = GroupStore(userDefaults: freshDefaults)
        defer {
            try? FileManager.default.removeItem(at: freshStore.backupDirectory)
            freshDefaults.removePersistentDomain(forName: "TestMRUExport")
        }

        try freshStore.importData(data)

        let importedGroup = freshStore.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(importedGroup?.mruOrder, ["com.test.1"])
    }

    func testUpdateMRUOrderCompositeIdPersistence() {
        let groupId = store.groups.first!.id
        let app = AppItem(bundleIdentifier: "com.chrome", name: "Chrome")
        store.addApp(app, to: groupId)

        // Store composite ID
        store.updateMRUOrder(activatedId: "com.chrome::200", activatedBundleId: "com.chrome", for: groupId, liveItemIds: Set(["com.chrome::200"]))

        let group = store.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group?.mruOrder, ["com.chrome::200"])

        // Verify persistence
        let store2 = GroupStore(userDefaults: userDefaults)
        let group2 = store2.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group2?.mruOrder, ["com.chrome::200"])
    }

    func testUpdateMRUOrderCompositeFiltering() {
        let groupId = store.groups.first!.id
        let app1 = AppItem(bundleIdentifier: "com.chrome", name: "Chrome")
        let app2 = AppItem(bundleIdentifier: "com.firefox", name: "Firefox")
        store.addApp(app1, to: groupId)
        store.addApp(app2, to: groupId)

        store.updateMRUOrder(activatedId: "com.chrome::100", activatedBundleId: "com.chrome", for: groupId, liveItemIds: Set(["com.chrome::100", "com.firefox::200"]))
        store.updateMRUOrder(activatedId: "com.firefox::200", activatedBundleId: "com.firefox", for: groupId, liveItemIds: Set(["com.chrome::100", "com.firefox::200"]))

        // Remove chrome from group — composite entries for chrome should be filtered
        store.removeApp(app1, from: groupId)
        store.updateMRUOrder(activatedId: "com.firefox::200", activatedBundleId: "com.firefox", for: groupId, liveItemIds: Set(["com.firefox::200"]))

        let group = store.groups.first(where: { $0.id == groupId })
        XCTAssertEqual(group?.mruOrder, ["com.firefox::200"])
    }

    func testFlushWithNoPendingBackupIsNoOp() {
        // Create a fresh store, don't make any changes
        let freshDefaults = UserDefaults(suiteName: "TestFlushNoOp")!
        freshDefaults.removePersistentDomain(forName: "TestFlushNoOp")
        let freshStore = GroupStore(userDefaults: freshDefaults)
        defer {
            try? FileManager.default.removeItem(at: freshStore.backupDirectory)
            freshDefaults.removePersistentDomain(forName: "TestFlushNoOp")
        }

        // Flush with nothing pending — should not crash or create files
        freshStore.flushPendingBackup()
    }

    // MARK: - Termination Observer

    func testTerminationObserverFlushesBackup() {
        let freshDefaults = UserDefaults(suiteName: "TestTermination")!
        freshDefaults.removePersistentDomain(forName: "TestTermination")
        let freshStore = GroupStore(userDefaults: freshDefaults)
        defer {
            try? FileManager.default.removeItem(at: freshStore.backupDirectory)
            freshDefaults.removePersistentDomain(forName: "TestTermination")
        }

        // First change triggers immediate backup
        _ = freshStore.addGroup(name: "First")

        // Wait to ensure different backup timestamp (filenames use second precision)
        Thread.sleep(forTimeInterval: 1.1)

        // Second change within debounce window leaves backup pending
        _ = freshStore.addGroup(name: "Second")

        let fm = FileManager.default
        let countBefore = ((try? fm.contentsOfDirectory(at: freshStore.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        // Post will-terminate to trigger the observer callback
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)

        let countAfter = ((try? fm.contentsOfDirectory(at: freshStore.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        XCTAssertGreaterThan(countAfter, countBefore)
    }

    // MARK: - contentEqual decode-failure fallback

    func testContentEqualFallbackOnInvalidJSON() {
        let freshDefaults = UserDefaults(suiteName: "TestContentEqual")!
        freshDefaults.removePersistentDomain(forName: "TestContentEqual")
        let freshStore = GroupStore(userDefaults: freshDefaults)
        defer {
            try? FileManager.default.removeItem(at: freshStore.backupDirectory)
            freshDefaults.removePersistentDomain(forName: "TestContentEqual")
        }

        // Write a non-JSON file that looks like a backup
        let fakeBackup = freshStore.backupDirectory.appendingPathComponent("backup 9999-12-31 23-59-59.json")
        try? "not json".data(using: .utf8)!.write(to: fakeBackup)

        // manualBackup calls contentEqual which will fail to decode the fake file
        // and fall back to raw data comparison (a != b), so it should save a new backup
        _ = freshStore.addGroup(name: "Test")
        let result = freshStore.manualBackup()
        XCTAssertEqual(result, .saved)
    }

    // MARK: - Cleanup old backups

    func testCleanupOldBackupsEnforcesRetention() {
        let freshDefaults = UserDefaults(suiteName: "TestCleanup")!
        freshDefaults.removePersistentDomain(forName: "TestCleanup")
        let freshStore = GroupStore(userDefaults: freshDefaults)
        defer {
            try? FileManager.default.removeItem(at: freshStore.backupDirectory)
            freshDefaults.removePersistentDomain(forName: "TestCleanup")
        }

        // Create 150 fake backup files with staggered timestamps
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"

        for i in 0..<150 {
            let date = Date().addingTimeInterval(Double(-i * 10))
            let name = "backup \(formatter.string(from: date)).json"
            let url = freshStore.backupDirectory.appendingPathComponent(name)
            try? "{}".data(using: .utf8)!.write(to: url)
        }

        // Trigger a real backup which also runs cleanupOldBackups
        _ = freshStore.addGroup(name: "Trigger Cleanup")
        freshStore.flushPendingBackup()

        let files = (try? fm.contentsOfDirectory(at: freshStore.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []

        // After cleanup, file count should be capped at ~100
        XCTAssertLessThanOrEqual(files.count, 101)
    }

    // MARK: - Timer debounce callback

    func testTimerDebounceCallbackFires() {
        let freshDefaults = UserDefaults(suiteName: "TestTimerDebounce")!
        freshDefaults.removePersistentDomain(forName: "TestTimerDebounce")
        let freshStore = GroupStore(userDefaults: freshDefaults, backupDebounceInterval: 0.05)
        defer {
            try? FileManager.default.removeItem(at: freshStore.backupDirectory)
            freshDefaults.removePersistentDomain(forName: "TestTimerDebounce")
        }

        // First change triggers immediate backup
        _ = freshStore.addGroup(name: "First")

        // Wait to ensure different backup timestamp (filenames use second precision)
        Thread.sleep(forTimeInterval: 1.1)

        let fm = FileManager.default
        let countAfterFirst = ((try? fm.contentsOfDirectory(at: freshStore.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        // Second change within debounce → pending, timer started
        _ = freshStore.addGroup(name: "Second")

        // Let the timer fire
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let countAfterTimer = ((try? fm.contentsOfDirectory(at: freshStore.backupDirectory, includingPropertiesForKeys: nil))?.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        } ?? []).count

        XCTAssertGreaterThan(countAfterTimer, countAfterFirst)
    }
}

// Make ManualBackupResult equatable for test assertions
extension ManualBackupResult: Equatable {
    public static func == (lhs: ManualBackupResult, rhs: ManualBackupResult) -> Bool {
        switch (lhs, rhs) {
        case (.saved, .saved): return true
        case (.noChange, .noChange): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

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
}

// Make ManualBackupResult equatable for test assertions
extension ManualBackupResult: @retroactive Equatable {
    public static func == (lhs: ManualBackupResult, rhs: ManualBackupResult) -> Bool {
        switch (lhs, rhs) {
        case (.saved, .saved): return true
        case (.noChange, .noChange): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

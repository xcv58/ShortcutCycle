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
        userDefaults.removePersistentDomain(forName: "TestDefaults")
        store = nil
        userDefaults = nil
        super.tearDown()
    }
    
    func testInitialState() {
        // Defaults should be created
        XCTAssertEqual(store.groups.count, 2)
        XCTAssertEqual(store.groups.first?.name, "Browsers")
    }
    
    func testAddGroup() {
        let count = store.groups.count
        let newGroup = store.addGroup(name: "New Group")
        
        XCTAssertEqual(store.groups.count, count + 1)
        XCTAssertEqual(newGroup.name, "New Group")
        XCTAssertEqual(store.selectedGroupId, newGroup.id)
    }
    
    func testDeleteGroup() {
        let group = store.groups.first!
        store.deleteGroup(group)
        
        XCTAssertFalse(store.groups.contains(where: { $0.id == group.id }))
    }
    
    func testUpdateGroup() {
        var group = store.groups.first!
        group.name = "Updated Name"

        store.updateGroup(group)

        XCTAssertEqual(store.groups.first?.name, "Updated Name")
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

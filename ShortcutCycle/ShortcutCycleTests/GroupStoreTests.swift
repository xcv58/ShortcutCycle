import XCTest
@testable import ShortcutCycle

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
}

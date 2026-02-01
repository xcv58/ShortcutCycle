import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

final class AppGroupTests: XCTestCase {
    
    func testInitialization() {
        let name = "Test Group"
        let group = AppGroup(name: name)
        
        XCTAssertEqual(group.name, name)
        XCTAssertTrue(group.apps.isEmpty)
        XCTAssertTrue(group.isEnabled)
    }
    
    func testAddApp() {
        var group = AppGroup(name: "Test Group")
        let app = AppItem(bundleIdentifier: "com.test.app", name: "Test App", iconPath: nil)
        
        group.addApp(app)
        
        XCTAssertEqual(group.apps.count, 1)
        XCTAssertEqual(group.apps.first?.id, app.id)
    }
    
    func testAddDuplicateApp() {
        var group = AppGroup(name: "Test Group")
        let app = AppItem(bundleIdentifier: "com.test.app", name: "Test App", iconPath: nil)
        
        group.addApp(app)
        group.addApp(app) // Should handle duplicate gracefully
        
        XCTAssertEqual(group.apps.count, 1)
    }
    
    func testRemoveApp() {
        var group = AppGroup(name: "Test Group")
        let app = AppItem(bundleIdentifier: "com.test.app", name: "Test App", iconPath: nil)
        
        group.addApp(app)
        group.removeApp(app)
        
        XCTAssertTrue(group.apps.isEmpty)
    }
    
    func testMoveApp() {
        var group = AppGroup(name: "Test Group")
        let app1 = AppItem(bundleIdentifier: "com.test.1", name: "App 1", iconPath: nil)
        let app2 = AppItem(bundleIdentifier: "com.test.2", name: "App 2", iconPath: nil)
        
        group.addApp(app1)
        group.addApp(app2)
        
        // Move app1 (index 0) to end
        group.moveApp(from: IndexSet(integer: 0), to: 2)
        
        XCTAssertEqual(group.apps[0].id, app2.id)
        XCTAssertEqual(group.apps[1].id, app1.id)
    }
}

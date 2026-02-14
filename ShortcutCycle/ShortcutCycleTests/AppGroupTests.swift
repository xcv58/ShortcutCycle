import XCTest
import KeyboardShortcuts
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

final class AppGroupTests: XCTestCase {

    // MARK: - Initialization

    func testInitialization() {
        let name = "Test Group"
        let group = AppGroup(name: name)

        XCTAssertEqual(group.name, name)
        XCTAssertTrue(group.apps.isEmpty)
        XCTAssertTrue(group.isEnabled)
    }

    func testInitializationWithAllParameters() {
        let id = UUID()
        let app = AppItem(bundleIdentifier: "com.test.app", name: "Test")
        let date = Date(timeIntervalSince1970: 1000)
        let group = AppGroup(
            id: id,
            name: "Custom",
            apps: [app],
            isEnabled: false,
            openAppIfNeeded: true,
            lastModified: date
        )

        XCTAssertEqual(group.id, id)
        XCTAssertEqual(group.name, "Custom")
        XCTAssertEqual(group.apps.count, 1)
        XCTAssertFalse(group.isEnabled)
        XCTAssertEqual(group.openAppIfNeeded, true)
        XCTAssertEqual(group.lastModified, date)
    }

    func testDefaultIsEnabledTrue() {
        let group = AppGroup(name: "G")
        XCTAssertTrue(group.isEnabled)
    }

    func testDefaultOpenAppIfNeededNil() {
        let group = AppGroup(name: "G")
        XCTAssertNil(group.openAppIfNeeded)
    }

    // MARK: - shouldOpenAppIfNeeded

    func testShouldOpenAppIfNeededDefaultsFalse() {
        let group = AppGroup(name: "G")
        XCTAssertFalse(group.shouldOpenAppIfNeeded)
    }

    func testShouldOpenAppIfNeededWhenTrue() {
        let group = AppGroup(name: "G", openAppIfNeeded: true)
        XCTAssertTrue(group.shouldOpenAppIfNeeded)
    }

    func testShouldOpenAppIfNeededWhenExplicitlyFalse() {
        let group = AppGroup(name: "G", openAppIfNeeded: false)
        XCTAssertFalse(group.shouldOpenAppIfNeeded)
    }

    // MARK: - Add App

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

    func testAddDuplicateBundleIdDifferentUUID() {
        var group = AppGroup(name: "Test Group")
        let app1 = AppItem(bundleIdentifier: "com.test.app", name: "Test App 1")
        let app2 = AppItem(bundleIdentifier: "com.test.app", name: "Test App 2")

        group.addApp(app1)
        group.addApp(app2)

        // Dedup is by bundleIdentifier, so the second should be rejected
        XCTAssertEqual(group.apps.count, 1)
        XCTAssertEqual(group.apps.first?.name, "Test App 1")
    }

    func testAddAppUpdatesLastModified() {
        var group = AppGroup(name: "G", lastModified: Date.distantPast)
        let beforeAdd = group.lastModified

        group.addApp(AppItem(bundleIdentifier: "com.test", name: "T"))

        XCTAssertGreaterThan(group.lastModified, beforeAdd)
    }

    func testAddDuplicateDoesNotUpdateLastModified() {
        var group = AppGroup(name: "G")
        let app = AppItem(bundleIdentifier: "com.test", name: "T")
        group.addApp(app)
        let afterFirstAdd = group.lastModified

        // Adding duplicate should not change lastModified
        group.addApp(app)
        XCTAssertEqual(group.lastModified, afterFirstAdd)
    }

    func testAddMultipleApps() {
        var group = AppGroup(name: "G")
        let apps = (1...5).map { AppItem(bundleIdentifier: "com.test.\($0)", name: "App \($0)") }

        for app in apps {
            group.addApp(app)
        }

        XCTAssertEqual(group.apps.count, 5)
    }

    // MARK: - Remove App

    func testRemoveApp() {
        var group = AppGroup(name: "Test Group")
        let app = AppItem(bundleIdentifier: "com.test.app", name: "Test App", iconPath: nil)

        group.addApp(app)
        group.removeApp(app)

        XCTAssertTrue(group.apps.isEmpty)
    }

    func testRemoveAppUpdatesLastModified() {
        var group = AppGroup(name: "G", lastModified: Date.distantPast)
        let app = AppItem(bundleIdentifier: "com.test", name: "T")
        group.addApp(app)
        let beforeRemove = group.lastModified

        // Small wait to ensure timestamp differs
        group.removeApp(app)

        XCTAssertGreaterThanOrEqual(group.lastModified, beforeRemove)
    }

    func testRemoveNonexistentApp() {
        var group = AppGroup(name: "G")
        let app1 = AppItem(bundleIdentifier: "com.test.1", name: "App 1")
        let app2 = AppItem(bundleIdentifier: "com.test.2", name: "App 2")
        group.addApp(app1)

        // Removing an app not in the group should not crash or affect existing apps
        group.removeApp(app2)

        XCTAssertEqual(group.apps.count, 1)
        XCTAssertEqual(group.apps.first?.bundleIdentifier, "com.test.1")
    }

    func testRemoveFromEmptyGroup() {
        var group = AppGroup(name: "G")
        let app = AppItem(bundleIdentifier: "com.test", name: "T")

        // Should not crash
        group.removeApp(app)
        XCTAssertTrue(group.apps.isEmpty)
    }

    // MARK: - Move App

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

    func testMoveAppToSamePosition() {
        var group = AppGroup(name: "G")
        let app1 = AppItem(bundleIdentifier: "com.test.1", name: "App 1")
        let app2 = AppItem(bundleIdentifier: "com.test.2", name: "App 2")
        group.addApp(app1)
        group.addApp(app2)

        // Move index 0 to position 0 (no change)
        group.moveApp(from: IndexSet(integer: 0), to: 0)

        XCTAssertEqual(group.apps[0].bundleIdentifier, "com.test.1")
        XCTAssertEqual(group.apps[1].bundleIdentifier, "com.test.2")
    }

    func testMoveAppUpdatesLastModified() {
        var group = AppGroup(name: "G", lastModified: Date.distantPast)
        let app1 = AppItem(bundleIdentifier: "com.test.1", name: "App 1")
        let app2 = AppItem(bundleIdentifier: "com.test.2", name: "App 2")
        group.addApp(app1)
        group.addApp(app2)
        let beforeMove = group.lastModified

        group.moveApp(from: IndexSet(integer: 0), to: 2)

        XCTAssertGreaterThanOrEqual(group.lastModified, beforeMove)
    }

    func testMoveMultipleItems() {
        var group = AppGroup(name: "G")
        let apps = (1...4).map { AppItem(bundleIdentifier: "com.test.\($0)", name: "App \($0)") }
        for app in apps { group.addApp(app) }

        // Move first two items to end
        group.moveApp(from: IndexSet([0, 1]), to: 4)

        XCTAssertEqual(group.apps[0].bundleIdentifier, "com.test.3")
        XCTAssertEqual(group.apps[1].bundleIdentifier, "com.test.4")
        XCTAssertEqual(group.apps[2].bundleIdentifier, "com.test.1")
        XCTAssertEqual(group.apps[3].bundleIdentifier, "com.test.2")
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip() throws {
        let app = AppItem(bundleIdentifier: "com.test.app", name: "Test", iconPath: "/path/to/icon")
        let group = AppGroup(
            name: "Encoded",
            apps: [app],
            isEnabled: false,
            openAppIfNeeded: true
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(AppGroup.self, from: data)

        XCTAssertEqual(decoded.id, group.id)
        XCTAssertEqual(decoded.name, "Encoded")
        XCTAssertEqual(decoded.apps.count, 1)
        XCTAssertEqual(decoded.apps.first?.bundleIdentifier, "com.test.app")
        XCTAssertFalse(decoded.isEnabled)
        XCTAssertEqual(decoded.openAppIfNeeded, true)
        XCTAssertTrue(decoded.shouldOpenAppIfNeeded)
    }

    func testCodableRoundTripWithLastActiveApp() throws {
        var group = AppGroup(name: "Active Test")
        group.lastActiveAppBundleId = "com.last.active"

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(AppGroup.self, from: data)

        XCTAssertEqual(decoded.lastActiveAppBundleId, "com.last.active")
    }

    func testCodableRoundTripPreservesAllFields() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1700000000)
        var group = AppGroup(
            id: id,
            name: "Full",
            apps: [
                AppItem(bundleIdentifier: "com.a", name: "A"),
                AppItem(bundleIdentifier: "com.b", name: "B")
            ],
            isEnabled: true,
            openAppIfNeeded: false,
            lastModified: date
        )
        group.lastActiveAppBundleId = "com.a"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(group)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppGroup.self, from: data)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Full")
        XCTAssertEqual(decoded.apps.count, 2)
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertEqual(decoded.openAppIfNeeded, false)
        XCTAssertEqual(decoded.lastActiveAppBundleId, "com.a")
    }

    func testDecodingWithoutOptionalFields() throws {
        // Simulate legacy data without openAppIfNeeded
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy",
            "apps": [],
            "isEnabled": true,
            "lastModified": 1000000
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppGroup.self, from: data)

        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertNil(decoded.openAppIfNeeded)
        XCTAssertFalse(decoded.shouldOpenAppIfNeeded)
        XCTAssertNil(decoded.lastActiveAppBundleId)
    }

    // MARK: - Equatable

    func testEquatable() {
        let id = UUID()
        let group1 = AppGroup(id: id, name: "Same")
        let group2 = AppGroup(id: id, name: "Same")

        XCTAssertEqual(group1, group2)
    }

    func testNotEqualDifferentName() {
        let id = UUID()
        let group1 = AppGroup(id: id, name: "One")
        let group2 = AppGroup(id: id, name: "Two")

        XCTAssertNotEqual(group1, group2)
    }

    func testNotEqualDifferentId() {
        let group1 = AppGroup(name: "Same")
        let group2 = AppGroup(name: "Same")

        XCTAssertNotEqual(group1, group2)
    }

    // MARK: - Shortcut Properties

    func testShortcutNameIsConsistent() {
        let id = UUID()
        let group = AppGroup(id: id, name: "Test")

        // shortcutName should be deterministic based on group ID
        let name1 = group.shortcutName
        let name2 = group.shortcutName
        XCTAssertEqual(name1, name2)
    }

    @MainActor
    func testHasShortcutDefaultsFalse() {
        let group = AppGroup(name: "No Shortcut")

        // No shortcut registered in test environment
        XCTAssertFalse(group.hasShortcut)
    }

    @MainActor
    func testShortcutDisplayStringDefaultsNil() {
        let group = AppGroup(name: "No Shortcut")

        // No shortcut registered in test environment
        XCTAssertNil(group.shortcutDisplayString)
    }

    // MARK: - Legacy Shortcut Decoding

    func testDecodingWithLegacyShortcutField() throws {
        // Legacy data that includes the old 'shortcut' field
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy With Shortcut",
            "apps": [],
            "isEnabled": true,
            "lastModified": 1000000,
            "shortcut": {
                "keyCode": 0,
                "modifiers": 256
            }
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppGroup.self, from: data)

        // Should decode without error, ignoring the legacy shortcut field
        XCTAssertEqual(decoded.name, "Legacy With Shortcut")
    }

    func testShouldOpenAppIfNeededDefaultsToFalse() {
        let group = AppGroup(name: "Test Group", openAppIfNeeded: nil)
        XCTAssertFalse(group.shouldOpenAppIfNeeded)

        let enabled = AppGroup(name: "Enabled Group", openAppIfNeeded: true)
        XCTAssertTrue(enabled.shouldOpenAppIfNeeded)
    }

    func testShortcutNameAndNotificationName() {
        let group = AppGroup(name: "Shortcut Group")
        XCTAssertEqual(group.shortcutName, .forGroup(group.id))
        XCTAssertEqual(Notification.Name.shortcutsNeedUpdate.rawValue, "ShortcutsNeedUpdate")
    }

    @MainActor
    func testShortcutHelpersReflectKeyboardShortcuts() {
        let group = AppGroup(name: "Shortcut Group")
        let name = group.shortcutName

        KeyboardShortcuts.setShortcut(nil, for: name)
        XCTAssertFalse(group.hasShortcut)
        XCTAssertNil(group.shortcutDisplayString)

        let shortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: 0, carbonModifiers: 256)
        KeyboardShortcuts.setShortcut(shortcut, for: name)

        XCTAssertTrue(group.hasShortcut)
        XCTAssertEqual(group.shortcutDisplayString, shortcut.description)

        KeyboardShortcuts.setShortcut(nil, for: name)
    }
}

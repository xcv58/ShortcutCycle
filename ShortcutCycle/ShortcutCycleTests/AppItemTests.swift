import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

final class AppItemTests: XCTestCase {

    // MARK: - Initialization

    func testInitialization() {
        let item = AppItem(bundleIdentifier: "com.test.app", name: "Test App")

        XCTAssertEqual(item.bundleIdentifier, "com.test.app")
        XCTAssertEqual(item.name, "Test App")
        XCTAssertNil(item.iconPath)
    }

    func testInitializationWithIconPath() {
        let item = AppItem(bundleIdentifier: "com.test.app", name: "Test", iconPath: "/path/to/icon.png")

        XCTAssertEqual(item.iconPath, "/path/to/icon.png")
    }

    func testInitializationWithExplicitId() {
        let id = UUID()
        let item = AppItem(id: id, bundleIdentifier: "com.test.app", name: "Test")

        XCTAssertEqual(item.id, id)
    }

    func testUniqueIdsForDifferentInstances() {
        let item1 = AppItem(bundleIdentifier: "com.test.app", name: "Test")
        let item2 = AppItem(bundleIdentifier: "com.test.app", name: "Test")

        XCTAssertNotEqual(item1.id, item2.id)
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip() throws {
        let original = AppItem(bundleIdentifier: "com.test.app", name: "Test App", iconPath: "/icon.png")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppItem.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.bundleIdentifier, "com.test.app")
        XCTAssertEqual(decoded.name, "Test App")
        XCTAssertEqual(decoded.iconPath, "/icon.png")
    }

    func testCodableRoundTripWithNilIconPath() throws {
        let original = AppItem(bundleIdentifier: "com.test.app", name: "Test")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppItem.self, from: data)

        XCTAssertNil(decoded.iconPath)
    }

    // MARK: - Equatable

    func testEqualSameId() {
        let id = UUID()
        let item1 = AppItem(id: id, bundleIdentifier: "com.test.app", name: "Test")
        let item2 = AppItem(id: id, bundleIdentifier: "com.test.app", name: "Test")

        XCTAssertEqual(item1, item2)
    }

    func testNotEqualDifferentId() {
        let item1 = AppItem(bundleIdentifier: "com.test.app", name: "Test")
        let item2 = AppItem(bundleIdentifier: "com.test.app", name: "Test")

        XCTAssertNotEqual(item1, item2)
    }

    // MARK: - Hashable

    func testHashable() {
        let id = UUID()
        let item1 = AppItem(id: id, bundleIdentifier: "com.test.app", name: "Test")
        let item2 = AppItem(id: id, bundleIdentifier: "com.test.app", name: "Test")

        var set = Set<AppItem>()
        set.insert(item1)
        set.insert(item2)

        XCTAssertEqual(set.count, 1)
    }

    func testHashableDifferentItems() {
        let item1 = AppItem(bundleIdentifier: "com.test.1", name: "App 1")
        let item2 = AppItem(bundleIdentifier: "com.test.2", name: "App 2")

        var set = Set<AppItem>()
        set.insert(item1)
        set.insert(item2)

        XCTAssertEqual(set.count, 2)
    }

    // MARK: - from(appURL:)

    func testFromInvalidURL() {
        let url = URL(fileURLWithPath: "/nonexistent/path/FakeApp.app")
        let item = AppItem.from(appURL: url)

        XCTAssertNil(item)
    }

    func testFromNonAppURL() {
        // Create a temporary non-app directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let item = AppItem.from(appURL: tempDir)

        // Not a valid .app bundle, so should return nil (no bundle ID)
        XCTAssertNil(item)
    }
}

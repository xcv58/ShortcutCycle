import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

/// Smoke tests for basic type conformances across the Core module
final class ShortcutCycleTests: XCTestCase {

    // MARK: - CyclingAppItem

    func testCyclingAppItemIdentifiable() {
        let item = CyclingAppItem(id: "com.test.app")
        XCTAssertEqual(item.id, "com.test.app")
    }

    func testCyclingAppItemEquatable() {
        let a = CyclingAppItem(id: "com.test.app")
        let b = CyclingAppItem(id: "com.test.app")
        let c = CyclingAppItem(id: "com.other.app")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - ResolvableAppItem

    func testResolvableAppItemProperties() {
        let item = ResolvableAppItem(id: "com.test.app-100", bundleId: "com.test.app")
        XCTAssertEqual(item.id, "com.test.app-100")
        XCTAssertEqual(item.bundleId, "com.test.app")
    }

    // MARK: - DiffStatus

    func testDiffStatusEquatable() {
        XCTAssertEqual(DiffStatus.added, DiffStatus.added)
        XCTAssertEqual(DiffStatus.removed, DiffStatus.removed)
        XCTAssertEqual(DiffStatus.modified, DiffStatus.modified)
        XCTAssertEqual(DiffStatus.unchanged, DiffStatus.unchanged)
        XCTAssertNotEqual(DiffStatus.added, DiffStatus.removed)
    }

    // MARK: - AppCyclingLogic edge case

    func testNextAppIdWithEmptyItems() {
        let result = AppCyclingLogic.nextAppId(
            items: [],
            currentFrontmostAppId: nil,
            currentHUDSelectionId: nil,
            lastActiveAppId: nil,
            isHUDVisible: false
        )
        XCTAssertEqual(result, "")
    }

    func testNextAppIdSingleItem() {
        let items = [CyclingAppItem(id: "com.single.app")]
        let result = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.single.app",
            currentHUDSelectionId: nil,
            lastActiveAppId: nil,
            isHUDVisible: false
        )
        // Single item wraps around to itself
        XCTAssertEqual(result, "com.single.app")
    }
}

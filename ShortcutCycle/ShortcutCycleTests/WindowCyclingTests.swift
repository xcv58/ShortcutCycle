import XCTest
import Foundation
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

/// Tests for per-window cycling: 4-tier resolution, MRU sorting with window IDs,
/// MRU update evicting closed windows, and backward compatibility.
final class WindowCyclingTests: XCTestCase {

    // MARK: - resolveLastActiveId: 4-tier matching

    func testTier1ExactMatchOnWindowId() {
        let items = [
            ResolvableAppItem(id: "com.app::100::w0", bundleId: "com.app"),
            ResolvableAppItem(id: "com.app::100::w1", bundleId: "com.app"),
        ]
        let result = AppCyclingLogic.resolveLastActiveId(storedId: "com.app::100::w1", items: items)
        XCTAssertEqual(result, "com.app::100::w1")
    }

    func testTier2PlainBundleIdMatch() {
        let items = [
            ResolvableAppItem(id: "com.app::200::w0", bundleId: "com.app"),
        ]
        // Stored as plain bundle ID, should match the first item with that bundle ID
        let result = AppCyclingLogic.resolveLastActiveId(storedId: "com.app", items: items)
        XCTAssertEqual(result, "com.app::200::w0")
    }

    func testTier3ProcessLevelPrefixMatch() {
        // Stored window w0 no longer exists, but w2 from same PID does
        let items = [
            ResolvableAppItem(id: "com.app::100::w2", bundleId: "com.app"),
            ResolvableAppItem(id: "com.app::200::w0", bundleId: "com.app"),
        ]
        let result = AppCyclingLogic.resolveLastActiveId(storedId: "com.app::100::w0", items: items)
        XCTAssertEqual(result, "com.app::100::w2")
    }

    func testTier4BundleIdPrefixFallbackForStalePid() {
        // Stored PID 100 no longer exists, but PID 300 of same app does
        let items = [
            ResolvableAppItem(id: "com.app::300::w0", bundleId: "com.app"),
        ]
        let result = AppCyclingLogic.resolveLastActiveId(storedId: "com.app::100::w0", items: items)
        XCTAssertEqual(result, "com.app::300::w0")
    }

    func testNoMatchReturnsNil() {
        let items = [
            ResolvableAppItem(id: "com.other::100::w0", bundleId: "com.other"),
        ]
        let result = AppCyclingLogic.resolveLastActiveId(storedId: "com.app::100::w0", items: items)
        XCTAssertNil(result)
    }

    func testNilStoredIdReturnsNil() {
        let items = [
            ResolvableAppItem(id: "com.app::100::w0", bundleId: "com.app"),
        ]
        let result = AppCyclingLogic.resolveLastActiveId(storedId: nil, items: items)
        XCTAssertNil(result)
    }

    // MARK: - resolveLastActiveId: backward compatibility (3-tier still works)

    func testBackwardCompatExactCompositeIdWithoutWindow() {
        let items = [
            ResolvableAppItem(id: "com.app::100", bundleId: "com.app"),
        ]
        let result = AppCyclingLogic.resolveLastActiveId(storedId: "com.app::100", items: items)
        XCTAssertEqual(result, "com.app::100")
    }

    func testBackwardCompatBundlePrefixFallback() {
        let items = [
            ResolvableAppItem(id: "com.app::200", bundleId: "com.app"),
        ]
        // Stored "com.app::100" (old PID), should fall back to another instance
        let result = AppCyclingLogic.resolveLastActiveId(storedId: "com.app::100", items: items)
        XCTAssertEqual(result, "com.app::200")
    }

    // MARK: - sortedByMRU with window IDs

    func testMRUSortWithWindowIds() {
        // 3 windows, MRU order says w1 was most recent, then w0
        let itemIds = ["com.app::100::w0", "com.app::100::w1", "com.app::100::w2"]
        let itemBundleIds = ["com.app", "com.app", "com.app"]
        let mruOrder = ["com.app::100::w1", "com.app::100::w0"]
        let groupBundleIds = ["com.app"]

        let sorted = AppCyclingLogic.sortedByMRU(
            itemIds: itemIds,
            itemBundleIds: itemBundleIds,
            mruOrder: mruOrder,
            groupBundleIds: groupBundleIds
        )

        // w1 (index 1) should be first, w0 (index 0) second, w2 (index 2) last
        XCTAssertEqual(sorted, [1, 0, 2])
    }

    func testMRUSortProcessPrefixMatchForWindowIds() {
        // MRU has an entry for w0 of PID 100. A new window w3 exists for same PID.
        // w3 should match via process-level prefix.
        let itemIds = ["com.app::100::w0", "com.app::100::w3"]
        let itemBundleIds = ["com.app", "com.app"]
        let mruOrder = ["com.app::100::w0"]
        let groupBundleIds = ["com.app"]

        let sorted = AppCyclingLogic.sortedByMRU(
            itemIds: itemIds,
            itemBundleIds: itemBundleIds,
            mruOrder: mruOrder,
            groupBundleIds: groupBundleIds
        )

        // w0 is exact match (rank 0), w3 matches via process prefix (also rank 0 from same entry),
        // but w0 has lower original index, so w0 first, w3 second
        XCTAssertEqual(sorted, [0, 1])
    }

    func testMRUSortMixedWindowAndProcessLevelItems() {
        // Mix of process-level items and per-window items
        let itemIds = ["com.chrome::100::w0", "com.chrome::100::w1", "com.safari::200"]
        let itemBundleIds = ["com.chrome", "com.chrome", "com.safari"]
        let mruOrder = ["com.safari::200", "com.chrome::100::w1"]
        let groupBundleIds = ["com.chrome", "com.safari"]

        let sorted = AppCyclingLogic.sortedByMRU(
            itemIds: itemIds,
            itemBundleIds: itemBundleIds,
            mruOrder: mruOrder,
            groupBundleIds: groupBundleIds
        )

        // safari::200 is rank 0 (exact), chrome w1 is rank 1 (exact),
        // chrome w0 matches via process prefix (after explicit MRU entries)
        XCTAssertEqual(sorted, [2, 1, 0])
    }

    // MARK: - updatedMRUOrder with window IDs

    func testMRUUpdateWithWindowId() {
        let current = ["com.app::100::w0", "com.app::100::w1"]
        let result = AppCyclingLogic.updatedMRUOrder(
            currentOrder: current,
            activatedId: "com.app::100::w1",
            activatedBundleId: "com.app",
            validBundleIds: Set(["com.app"]),
            liveItemIds: Set(["com.app::100::w0", "com.app::100::w1"])
        )
        // w1 should move to front
        XCTAssertEqual(result, ["com.app::100::w1", "com.app::100::w0"])
    }

    func testMRUUpdateEvictsClosedWindow() {
        let current = ["com.app::100::w0", "com.app::100::w1", "com.app::100::w2"]
        // w2 is no longer live (window was closed)
        let result = AppCyclingLogic.updatedMRUOrder(
            currentOrder: current,
            activatedId: "com.app::100::w0",
            activatedBundleId: "com.app",
            validBundleIds: Set(["com.app"]),
            liveItemIds: Set(["com.app::100::w0", "com.app::100::w1"])
        )
        // w0 at front, w1 kept, w2 evicted
        XCTAssertEqual(result, ["com.app::100::w0", "com.app::100::w1"])
    }

    func testMRUUpdateNewWindowIdAdded() {
        // New window that wasn't in MRU before
        let current = ["com.app::100::w0"]
        let result = AppCyclingLogic.updatedMRUOrder(
            currentOrder: current,
            activatedId: "com.app::100::w2",
            activatedBundleId: "com.app",
            validBundleIds: Set(["com.app"]),
            liveItemIds: Set(["com.app::100::w0", "com.app::100::w2"])
        )
        XCTAssertEqual(result, ["com.app::100::w2", "com.app::100::w0"])
    }

    // MARK: - nextAppId with window IDs

    func testNextAppIdCyclesThroughWindows() {
        let items = [
            CyclingAppItem(id: "com.app::100::w0"),
            CyclingAppItem(id: "com.app::100::w1"),
            CyclingAppItem(id: "com.app::100::w2"),
        ]

        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: nil,
            currentHUDSelectionId: "com.app::100::w0",
            lastActiveAppId: nil,
            isHUDVisible: true
        )
        XCTAssertEqual(next, "com.app::100::w1")
    }

    func testNextAppIdWrapsAroundWindows() {
        let items = [
            CyclingAppItem(id: "com.app::100::w0"),
            CyclingAppItem(id: "com.app::100::w1"),
        ]

        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: nil,
            currentHUDSelectionId: "com.app::100::w1",
            lastActiveAppId: nil,
            isHUDVisible: true
        )
        XCTAssertEqual(next, "com.app::100::w0")
    }
}

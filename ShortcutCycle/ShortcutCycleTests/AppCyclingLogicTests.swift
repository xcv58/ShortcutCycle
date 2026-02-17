import XCTest
import Foundation
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

// Assuming AppCyclingLogic.swift is included in the target sources
// @testable import ShortcutCycle // Not needed if file included directly

final class AppCyclingLogicTests: XCTestCase {
    
    // MARK: - Helpers
    
    // Helper to create items
    func makeItems(_ ids: [String]) -> [CyclingAppItem] {
        return ids.map { CyclingAppItem(id: $0) }
    }
    
    // MARK: - Tests
    
    func testHUDVisibleNextItem() {
        let items = makeItems(["com.app.A", "com.app.B", "com.app.C"])
        
        // Given HUD is visible and B is selected
        // Expect Next is C
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.app.A", // Irrelevant if HUD visible
            currentHUDSelectionId: "com.app.B",
            lastActiveAppId: nil,
            isHUDVisible: true
        )
        
        XCTAssertEqual(next, "com.app.C")
    }
    
    func testHUDVisibleWrapAround() {
        let items = makeItems(["com.app.A", "com.app.B"])
        
        // Given HUD visible and B (last) is selected
        // Expect Wrap to A
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.app.A", // Irrelevant
            currentHUDSelectionId: "com.app.B",
            lastActiveAppId: nil,
            isHUDVisible: true
        )
        
        XCTAssertEqual(next, "com.app.A")
    }
    
    func testHUDVisibleUnknownSelection() {
        let items = makeItems(["com.app.A", "com.app.B"])
        
        // Given HUD visible but selected ID is unknown (e.g. app closed?)
        // Expect Default to First (A)
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.app.A",
            currentHUDSelectionId: "com.app.Z",
            lastActiveAppId: nil,
            isHUDVisible: true
        )
        
        XCTAssertEqual(next, "com.app.A")
    }
    
    func testNewCycleFrontmostInGroup() {
        let items = makeItems(["com.app.A", "com.app.B", "com.app.C"])
        
        // Given Frontmost is A
        // Expect B
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.app.A",
            currentHUDSelectionId: nil, // HUD not visible
            lastActiveAppId: "com.app.C", // Irrelevant if Frontmost is in group
            isHUDVisible: false
        )
        
        XCTAssertEqual(next, "com.app.B")
    }

    func testNewCycleFrontmostInGroupWithoutPrioritizingFrontmost_UsesLastActive() {
        let items = makeItems(["com.app.A", "com.app.B", "com.app.C"])

        // Cross-group entry should resume group context instead of stepping from frontmost.
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.app.A",
            currentHUDSelectionId: nil,
            lastActiveAppId: "com.app.C",
            isHUDVisible: false,
            prioritizeFrontmost: false
        )

        XCTAssertEqual(next, "com.app.C")
    }

    func testNewCycleFrontmostInGroupWithoutPrioritizingFrontmost_NoLastActiveUsesFirst() {
        let items = makeItems(["com.app.A", "com.app.B", "com.app.C"])

        // If there is no group context yet, default to first item.
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.app.A",
            currentHUDSelectionId: nil,
            lastActiveAppId: nil,
            isHUDVisible: false,
            prioritizeFrontmost: false
        )

        XCTAssertEqual(next, "com.app.A")
    }
    
    func testNewCycleFrontmostNotInGroupWithLastActive() {
        let items = makeItems(["com.app.A", "com.app.B", "com.app.C"])
        
        // Given Frontmost is Finder (not in group)
        // And Last Active was B
        // Expect Switch back to B (resume session)
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder",
            currentHUDSelectionId: nil,
            lastActiveAppId: "com.app.B",
            isHUDVisible: false
        )
        
        XCTAssertEqual(next, "com.app.B")
    }
    
    func testNewCycleFrontmostNotInGroupNoLastActive() {
        let items = makeItems(["com.app.A", "com.app.B"])

        // Given Frontmost Finder
        // Last active nil or unknown
        // Expect First (A)
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder",
            currentHUDSelectionId: nil,
            lastActiveAppId: "com.app.Z", // Unknown
            isHUDVisible: false
        )

        XCTAssertEqual(next, "com.app.A")
    }

    // MARK: - Multi-Profile (composite ID) Tests

    func testCompositeIdsCycleCorrectly() {
        // Multiple instances of same app have composite "bundleId::pid" IDs
        let items = makeItems(["com.google.Chrome::100", "com.google.Chrome::200", "com.app.B::300"])

        // Frontmost is first Chrome instance, expect next Chrome instance
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.google.Chrome::100",
            currentHUDSelectionId: nil,
            lastActiveAppId: nil,
            isHUDVisible: false
        )

        XCTAssertEqual(next, "com.google.Chrome::200")
    }

    func testCompositeIdsHUDCycling() {
        // HUD visible, cycling through multi-instance items
        let items = makeItems(["com.google.Chrome::100", "com.google.Chrome::200", "com.app.B::300"])

        // HUD shows Chrome-200, expect next is B-300
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.google.Chrome::100",
            currentHUDSelectionId: "com.google.Chrome::200",
            lastActiveAppId: nil,
            isHUDVisible: true
        )

        XCTAssertEqual(next, "com.app.B::300")
    }

    func testCompositeIdsWrapAround() {
        let items = makeItems(["com.google.Chrome::100", "com.google.Chrome::200"])

        // HUD shows last item, expect wrap to first
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: nil,
            currentHUDSelectionId: "com.google.Chrome::200",
            lastActiveAppId: nil,
            isHUDVisible: true
        )

        XCTAssertEqual(next, "com.google.Chrome::100")
    }

    func testResolvedLastActiveIdMatchesCompositeItem() {
        // Simulates the caller resolving a stored plain bundle ID to a composite ID
        // before calling nextAppId (as AppSwitcher now does)
        let items = makeItems(["com.google.Chrome::500", "com.app.B::600"])

        // lastActiveAppId has been pre-resolved to the composite ID by the caller
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder", // Not in group
            currentHUDSelectionId: nil,
            lastActiveAppId: "com.google.Chrome::500", // Resolved composite ID
            isHUDVisible: false
        )

        // Should resume to last active (Chrome instance)
        XCTAssertEqual(next, "com.google.Chrome::500")
    }

    func testUnresolvedPlainBundleIdFallsToFirst() {
        // If lastActiveAppId is a plain bundle ID that doesn't match any composite item,
        // the cycling logic should fall through to the first item
        let items = makeItems(["com.google.Chrome::500", "com.app.B::600"])

        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder",
            currentHUDSelectionId: nil,
            lastActiveAppId: "com.google.Chrome", // Plain ID, won't match composite
            isHUDVisible: false
        )

        // Falls through to first item since no match
        XCTAssertEqual(next, "com.google.Chrome::500")
    }

    // MARK: - Multi-Instance Last Active Regression Tests

    func testCompositeLastActiveIdReturnsCorrectInstance() {
        // Regression test: with 3 instances of the same app (e.g., Firefox profiles A, B, C),
        // if the user was on instance C (PID 300) and switched away, the shortcut should
        // return to C, not A (the first by PID).
        let items = makeItems([
            "org.mozilla.firefox::100",  // Profile A
            "org.mozilla.firefox::200",  // Profile B
            "org.mozilla.firefox::300"   // Profile C
        ])

        // User was on profile C, switched to Finder, now hits shortcut
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder::999",
            currentHUDSelectionId: nil,
            lastActiveAppId: "org.mozilla.firefox::300", // Composite ID for profile C
            isHUDVisible: false
        )

        // Should return to profile C (last active), not profile A
        XCTAssertEqual(next, "org.mozilla.firefox::300")
    }

    func testCompositeLastActiveIdMiddleInstance() {
        // Same regression test but for the middle instance
        let items = makeItems([
            "org.mozilla.firefox::100",  // Profile A
            "org.mozilla.firefox::200",  // Profile B
            "org.mozilla.firefox::300"   // Profile C
        ])

        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder::999",
            currentHUDSelectionId: nil,
            lastActiveAppId: "org.mozilla.firefox::200", // Profile B
            isHUDVisible: false
        )

        XCTAssertEqual(next, "org.mozilla.firefox::200")
    }

    // MARK: - resolveLastActiveId Tests

    func makeResolvable(_ pairs: [(id: String, bundleId: String)]) -> [ResolvableAppItem] {
        pairs.map { ResolvableAppItem(id: $0.id, bundleId: $0.bundleId) }
    }

    func testResolveNilStoredId() {
        let items = makeResolvable([
            (id: "org.mozilla.firefox::100", bundleId: "org.mozilla.firefox")
        ])
        XCTAssertNil(AppCyclingLogic.resolveLastActiveId(storedId: nil, items: items))
    }

    func testResolveExactCompositeMatch() {
        // Stored composite ID matches a running instance exactly
        let items = makeResolvable([
            (id: "org.mozilla.firefox::100", bundleId: "org.mozilla.firefox"),
            (id: "org.mozilla.firefox::200", bundleId: "org.mozilla.firefox"),
            (id: "org.mozilla.firefox::300", bundleId: "org.mozilla.firefox")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox::300",
            items: items
        )
        // Must return the exact instance, not the first one
        XCTAssertEqual(resolved, "org.mozilla.firefox::300")
    }

    func testResolvePlainBundleIdBackwardCompat() {
        // Old stored plain bundle ID resolves to the first instance (backward compat)
        let items = makeResolvable([
            (id: "org.mozilla.firefox::100", bundleId: "org.mozilla.firefox"),
            (id: "org.mozilla.firefox::200", bundleId: "org.mozilla.firefox")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox",
            items: items
        )
        XCTAssertEqual(resolved, "org.mozilla.firefox::100")
    }

    func testResolveProfileClosedFallsBackToFirstRemaining() {
        // Profile C (PID 300) was last active but is now closed.
        // A (100) and B (200) are still running. Should fall back to first remaining.
        let items = makeResolvable([
            (id: "org.mozilla.firefox::100", bundleId: "org.mozilla.firefox"),
            (id: "org.mozilla.firefox::200", bundleId: "org.mozilla.firefox")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox::300",
            items: items
        )
        // PID 300 doesn't exist; prefix fallback matches first Firefox instance
        XCTAssertEqual(resolved, "org.mozilla.firefox::100")
    }

    func testResolveAllClosedNewInstanceCreated() {
        // All old Firefox instances closed, new profile D (PID 400) appeared
        let items = makeResolvable([
            (id: "org.mozilla.firefox::400", bundleId: "org.mozilla.firefox")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox::300",
            items: items
        )
        // Prefix fallback finds the new instance
        XCTAssertEqual(resolved, "org.mozilla.firefox::400")
    }

    func testResolveAllInstancesClosedDifferentAppRunning() {
        // All Firefox instances closed, only Chrome is running
        let items = makeResolvable([
            (id: "com.google.Chrome::500", bundleId: "com.google.Chrome")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox::300",
            items: items
        )
        // No Firefox instances at all — returns nil
        XCTAssertNil(resolved)
    }

    func testResolveNonRunningAppInOpenIfNeededMode() {
        // "Open App If Needed" mode: Firefox not running shows as plain bundle ID item
        let items = makeResolvable([
            (id: "org.mozilla.firefox", bundleId: "org.mozilla.firefox"),  // not running
            (id: "com.google.Chrome::500", bundleId: "com.google.Chrome")  // running
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox::300",
            items: items
        )
        // Prefix fallback: "org.mozilla.firefox::300" starts with "org.mozilla.firefox::"
        // matches the non-running Firefox item, which is correct — it will trigger a launch
        XCTAssertEqual(resolved, "org.mozilla.firefox")
    }

    func testResolveEmptyItems() {
        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox::300",
            items: []
        )
        XCTAssertNil(resolved)
    }

    func testResolveDoesNotCrossMatchDifferentApps() {
        // Ensure "com.app.foo::100" doesn't match "com.app.foobar" via prefix
        let items = makeResolvable([
            (id: "com.app.foobar::200", bundleId: "com.app.foobar")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "com.app.foo::100",
            items: items
        )
        // "com.app.foo::100" does NOT start with "com.app.foobar::"
        XCTAssertNil(resolved)
    }

    // MARK: - End-to-End Edge Case Tests (resolve + nextAppId)

    func testEndToEndProfileClosedActivatesFirstRemaining() {
        // Profile C closed, A and B still running, user is on Finder
        let resolvable = makeResolvable([
            (id: "org.mozilla.firefox::100", bundleId: "org.mozilla.firefox"),
            (id: "org.mozilla.firefox::200", bundleId: "org.mozilla.firefox")
        ])
        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox::300", items: resolvable
        )
        // Falls back to first Firefox instance
        XCTAssertEqual(resolved, "org.mozilla.firefox::100")

        let items = makeItems(["org.mozilla.firefox::100", "org.mozilla.firefox::200"])
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder::999",
            currentHUDSelectionId: nil,
            lastActiveAppId: resolved,
            isHUDVisible: false
        )
        // Activates profile A (first remaining Firefox instance)
        XCTAssertEqual(next, "org.mozilla.firefox::100")
    }

    func testEndToEndAllClosedNewProfileActivatesIt() {
        // All old Firefox gone, new profile D appeared, group also has Chrome
        let resolvable = makeResolvable([
            (id: "org.mozilla.firefox::400", bundleId: "org.mozilla.firefox"),
            (id: "com.google.Chrome::500", bundleId: "com.google.Chrome")
        ])
        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox::300", items: resolvable
        )
        XCTAssertEqual(resolved, "org.mozilla.firefox::400")

        let items = makeItems(["org.mozilla.firefox::400", "com.google.Chrome::500"])
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder::999",
            currentHUDSelectionId: nil,
            lastActiveAppId: resolved,
            isHUDVisible: false
        )
        // Activates the new Firefox instance (stays with Firefox, not Chrome)
        XCTAssertEqual(next, "org.mozilla.firefox::400")
    }

    // MARK: - MRU Sorting Tests

    func testSortedByMRU_NilOrder() {
        let ids = ["com.a", "com.b", "com.c"]
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: ids,
            itemBundleIds: ids,
            mruOrder: nil,
            groupBundleIds: ids
        )
        XCTAssertEqual(indices, [0, 1, 2])
    }

    func testSortedByMRU_EmptyOrder() {
        let ids = ["com.a", "com.b", "com.c"]
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: ids,
            itemBundleIds: ids,
            mruOrder: [],
            groupBundleIds: ids
        )
        XCTAssertEqual(indices, [0, 1, 2])
    }

    func testSortedByMRU_FullOrder() {
        let ids = ["com.a", "com.b", "com.c"]
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: ids,
            itemBundleIds: ids,
            mruOrder: ["com.c", "com.a", "com.b"],
            groupBundleIds: ids
        )
        XCTAssertEqual(indices, [2, 0, 1])
    }

    func testSortedByMRU_PartialOrder() {
        let ids = ["com.a", "com.b", "com.c", "com.d"]
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: ids,
            itemBundleIds: ids,
            mruOrder: ["com.c"],
            groupBundleIds: ids
        )
        // C first (MRU rank 0), then A, B, D in group order
        XCTAssertEqual(indices, [2, 0, 1, 3])
    }

    func testSortedByMRU_StaleEntries() {
        let ids = ["com.a", "com.b"]
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: ids,
            itemBundleIds: ids,
            mruOrder: ["com.x", "com.b", "com.a"],
            groupBundleIds: ids
        )
        // com.x ignored, B(rank 1), A(rank 2)
        XCTAssertEqual(indices, [1, 0])
    }

    func testSortedByMRU_MultiInstance() {
        // Two instances of com.b with composite IDs, mruOrder has plain entries
        let itemIds = ["com.a", "com.b::100", "com.b::200", "com.c"]
        let itemBundleIds = ["com.a", "com.b", "com.b", "com.c"]
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: itemIds,
            itemBundleIds: itemBundleIds,
            mruOrder: ["com.b", "com.c", "com.a"],
            groupBundleIds: ["com.a", "com.b", "com.c"]
        )
        // B instances at indices 1,2 (tier 2 match on "com.b", rank 0), C at 3 (rank 1), A at 0 (rank 2)
        XCTAssertEqual(indices, [1, 2, 3, 0])
    }

    func testSortedByMRU_SingleItem() {
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: ["com.a"],
            itemBundleIds: ["com.a"],
            mruOrder: ["com.a"],
            groupBundleIds: ["com.a"]
        )
        XCTAssertEqual(indices, [0])
    }

    func testSortedByMRU_UnknownBundleIdFallback() {
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: ["com.unknown", "com.a"],
            itemBundleIds: ["com.unknown", "com.a"],
            mruOrder: ["com.a"],
            groupBundleIds: ["com.a"]
        )
        // com.a has rank 0, com.unknown has fallback rank → com.a first
        XCTAssertEqual(indices, [1, 0])
    }

    // MARK: - Instance-Aware MRU Sorting Tests

    func testSortedByMRU_CompositeIds() {
        // Two Chrome instances get distinct ranks via composite ID matching
        let itemIds = ["com.chrome::100", "com.chrome::200", "com.app.B::300"]
        let itemBundleIds = ["com.chrome", "com.chrome", "com.app.B"]
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: itemIds,
            itemBundleIds: itemBundleIds,
            mruOrder: ["com.chrome::200", "com.app.B::300", "com.chrome::100"],
            groupBundleIds: ["com.chrome", "com.app.B"]
        )
        // chrome-200 (rank 0), B-300 (rank 1), chrome-100 (rank 2)
        XCTAssertEqual(indices, [1, 2, 0])
    }

    func testSortedByMRU_BackwardCompatPlainEntries() {
        // Old mruOrder with plain IDs still works via tier-2 matching
        let itemIds = ["com.chrome::100", "com.firefox::200"]
        let itemBundleIds = ["com.chrome", "com.firefox"]
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: itemIds,
            itemBundleIds: itemBundleIds,
            mruOrder: ["com.firefox", "com.chrome"],
            groupBundleIds: ["com.chrome", "com.firefox"]
        )
        // firefox (rank 0 via tier 2), chrome (rank 1 via tier 2)
        XCTAssertEqual(indices, [1, 0])
    }

    func testSortedByMRU_StalePidFallback() {
        // MRU has "com.chrome::999" (stale PID), current instance is "com.chrome::100"
        let itemIds = ["com.chrome::100", "com.app.B::200"]
        let itemBundleIds = ["com.chrome", "com.app.B"]
        let indices = AppCyclingLogic.sortedByMRU(
            itemIds: itemIds,
            itemBundleIds: itemBundleIds,
            mruOrder: ["com.chrome::999", "com.app.B::200"],
            groupBundleIds: ["com.chrome", "com.app.B"]
        )
        // chrome-100 matches "com.chrome::999" via tier 3 prefix (rank 0), B-200 exact (rank 1)
        XCTAssertEqual(indices, [0, 1])
    }

    // MARK: - MRU Update Tests

    func testUpdatedMRUOrder_FirstUse() {
        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: nil,
            activatedId: "com.a",
            activatedBundleId: "com.a",
            validBundleIds: Set(["com.a", "com.b", "com.c"]),
            liveItemIds: Set(["com.a", "com.b", "com.c"])
        )
        XCTAssertEqual(order, ["com.a"])
    }

    func testUpdatedMRUOrder_MoveToFront() {
        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: ["com.a", "com.b", "com.c"],
            activatedId: "com.c",
            activatedBundleId: "com.c",
            validBundleIds: Set(["com.a", "com.b", "com.c"]),
            liveItemIds: Set(["com.a", "com.b", "com.c"])
        )
        XCTAssertEqual(order, ["com.c", "com.a", "com.b"])
    }

    func testUpdatedMRUOrder_AlreadyFirst() {
        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: ["com.a", "com.b", "com.c"],
            activatedId: "com.a",
            activatedBundleId: "com.a",
            validBundleIds: Set(["com.a", "com.b", "com.c"]),
            liveItemIds: Set(["com.a", "com.b", "com.c"])
        )
        XCTAssertEqual(order, ["com.a", "com.b", "com.c"])
    }

    func testUpdatedMRUOrder_FiltersStale() {
        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: ["com.x", "com.a", "com.b"],
            activatedId: "com.b",
            activatedBundleId: "com.b",
            validBundleIds: Set(["com.a", "com.b"]),
            liveItemIds: Set(["com.a", "com.b"])
        )
        XCTAssertEqual(order, ["com.b", "com.a"])
    }

    func testUpdatedMRUOrder_NewApp() {
        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: ["com.a", "com.b"],
            activatedId: "com.d",
            activatedBundleId: "com.d",
            validBundleIds: Set(["com.a", "com.b", "com.d"]),
            liveItemIds: Set(["com.a", "com.b", "com.d"])
        )
        XCTAssertEqual(order, ["com.d", "com.a", "com.b"])
    }

    // MARK: - Instance-Aware MRU Update Tests

    func testUpdatedMRUOrder_CompositeId() {
        // Composite ID is stored, not plain bundle ID
        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: nil,
            activatedId: "com.chrome::200",
            activatedBundleId: "com.chrome",
            validBundleIds: Set(["com.chrome", "com.app.B"]),
            liveItemIds: Set(["com.chrome::200", "com.app.B::300"])
        )
        XCTAssertEqual(order, ["com.chrome::200"])
    }

    func testUpdatedMRUOrder_UpgradesPlainEntry() {
        // Old plain entry "com.chrome" gets replaced by composite "com.chrome::200"
        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: ["com.chrome", "com.app.B::300"],
            activatedId: "com.chrome::200",
            activatedBundleId: "com.chrome",
            validBundleIds: Set(["com.chrome", "com.app.B"]),
            liveItemIds: Set(["com.chrome::200", "com.app.B::300"])
        )
        // "com.chrome" removed (upgrade), "com.chrome::200" at front
        XCTAssertEqual(order, ["com.chrome::200", "com.app.B::300"])
    }

    func testUpdatedMRUOrder_TwoInstancesSameBundle() {
        // Two Chrome instances tracked independently
        let liveIds = Set(["com.chrome::100", "com.chrome::200"])
        var order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: nil,
            activatedId: "com.chrome::100",
            activatedBundleId: "com.chrome",
            validBundleIds: Set(["com.chrome"]),
            liveItemIds: liveIds
        )
        XCTAssertEqual(order, ["com.chrome::100"])

        order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: order,
            activatedId: "com.chrome::200",
            activatedBundleId: "com.chrome",
            validBundleIds: Set(["com.chrome"]),
            liveItemIds: liveIds
        )
        // Both composite entries kept, 200 at front
        XCTAssertEqual(order, ["com.chrome::200", "com.chrome::100"])

        // Switch back to 100
        order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: order,
            activatedId: "com.chrome::100",
            activatedBundleId: "com.chrome",
            validBundleIds: Set(["com.chrome"]),
            liveItemIds: liveIds
        )
        XCTAssertEqual(order, ["com.chrome::100", "com.chrome::200"])
    }

    func testUpdatedMRUOrder_FilterCompositeByPrefix() {
        // Composite entries for removed bundles are filtered out
        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: ["com.removed::100", "com.chrome::200"],
            activatedId: "com.chrome::100",
            activatedBundleId: "com.chrome",
            validBundleIds: Set(["com.chrome"]),
            liveItemIds: Set(["com.chrome::100", "com.chrome::200"])
        )
        // "com.removed::100" filtered out (not live and not a valid plain bundle ID)
        XCTAssertEqual(order, ["com.chrome::100", "com.chrome::200"])
    }

    // MARK: - Stale PID Eviction Tests

    func testUpdatedMRUOrder_StalePidRemoved() {
        // Old PID entry evicted when new PID is live
        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: ["com.chrome::100", "com.app.B::300"],
            activatedId: "com.chrome::500",
            activatedBundleId: "com.chrome",
            validBundleIds: Set(["com.chrome", "com.app.B"]),
            liveItemIds: Set(["com.chrome::500", "com.app.B::300"])
        )
        // "com.chrome::100" is stale (not in liveItemIds, not a plain bundle ID) → evicted
        XCTAssertEqual(order, ["com.chrome::500", "com.app.B::300"])
    }

    func testUpdatedMRUOrder_LivePidsKept() {
        // Multi-instance entries preserved when both are live
        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: ["com.chrome::200", "com.chrome::100"],
            activatedId: "com.app.B::300",
            activatedBundleId: "com.app.B",
            validBundleIds: Set(["com.chrome", "com.app.B"]),
            liveItemIds: Set(["com.chrome::100", "com.chrome::200", "com.app.B::300"])
        )
        // Both Chrome instances are live → both kept
        XCTAssertEqual(order, ["com.app.B::300", "com.chrome::200", "com.chrome::100"])
    }

    // MARK: - Stress Tests

    func testUpdatedMRUOrder_ClearsHundredsOfStalePids() {
        // 5 apps, each with 20 stale PID entries = 100 stale entries
        var staleOrder: [String] = []
        let bundles = ["com.a", "com.b", "com.c", "com.d", "com.e"]
        for bundle in bundles {
            for pid in 1...20 {
                staleOrder.append("\(bundle)::\(pid)")
            }
        }
        XCTAssertEqual(staleOrder.count, 100)

        // Live items: one instance per app with fresh PIDs
        let liveIds = Set(bundles.map { "\($0)::999" })

        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: staleOrder,
            activatedId: "com.a::999",
            activatedBundleId: "com.a",
            validBundleIds: Set(bundles),
            liveItemIds: liveIds
        )

        // Only live entries should survive
        for entry in order {
            XCTAssertTrue(
                liveIds.contains(entry) || bundles.contains(entry),
                "Stale entry should have been evicted: \(entry)"
            )
        }
        XCTAssertEqual(order.first, "com.a::999")
    }

    func testUpdatedMRUOrder_ClearsThousandsOfStalePids() {
        // 10 apps, each with 100 stale PID entries = 1000 stale entries
        var staleOrder: [String] = []
        let bundles = (0..<10).map { "com.app\($0)" }
        for bundle in bundles {
            for pid in 1...100 {
                staleOrder.append("\(bundle)::\(pid)")
            }
        }
        XCTAssertEqual(staleOrder.count, 1000)

        let liveIds = Set(bundles.map { "\($0)::9999" })

        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: staleOrder,
            activatedId: "com.app0::9999",
            activatedBundleId: "com.app0",
            validBundleIds: Set(bundles),
            liveItemIds: liveIds
        )

        // Zero stale entries should survive
        for entry in order {
            XCTAssertTrue(
                liveIds.contains(entry) || bundles.contains(entry),
                "Stale entry should have been evicted: \(entry)"
            )
        }
        XCTAssertEqual(order.first, "com.app0::9999")
    }

    func testUpdatedMRUOrder_MixedLiveAndStale() {
        // 500 entries: 250 stale, 250 live
        var mixedOrder: [String] = []
        let bundles = (0..<50).map { "com.app\($0)" }

        // 5 stale entries per app
        for bundle in bundles {
            for pid in 1...5 {
                mixedOrder.append("\(bundle)::\(pid)")
            }
        }
        // 5 live entries per app
        var liveIds = Set<String>()
        for bundle in bundles {
            for pid in 1000...1004 {
                let id = "\(bundle)::\(pid)"
                mixedOrder.append(id)
                liveIds.insert(id)
            }
        }
        XCTAssertEqual(mixedOrder.count, 500)
        XCTAssertEqual(liveIds.count, 250)

        let order = AppCyclingLogic.updatedMRUOrder(
            currentOrder: mixedOrder,
            activatedId: "com.app0::1000",
            activatedBundleId: "com.app0",
            validBundleIds: Set(bundles),
            liveItemIds: liveIds
        )

        // All live kept, all stale removed
        for entry in order {
            XCTAssertTrue(
                liveIds.contains(entry) || bundles.contains(entry),
                "Stale entry should have been evicted: \(entry)"
            )
        }
        // All live entries should be present (activated entry is always first)
        for liveId in liveIds {
            XCTAssertTrue(order.contains(liveId), "Live entry missing: \(liveId)")
        }
    }

    func testEndToEndAllFirefoxClosedFallsToNextApp() {
        // Firefox completely gone, only Chrome running
        let resolvable = makeResolvable([
            (id: "com.google.Chrome::500", bundleId: "com.google.Chrome")
        ])
        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox::300", items: resolvable
        )
        XCTAssertNil(resolved)

        let items = makeItems(["com.google.Chrome::500"])
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder::999",
            currentHUDSelectionId: nil,
            lastActiveAppId: resolved,
            isHUDVisible: false
        )
        // No Firefox at all — falls through to first item (Chrome)
        XCTAssertEqual(next, "com.google.Chrome::500")
    }
}

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
        // Multiple instances of same app have composite "bundleId-pid" IDs
        let items = makeItems(["com.google.Chrome-100", "com.google.Chrome-200", "com.app.B-300"])

        // Frontmost is first Chrome instance, expect next Chrome instance
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.google.Chrome-100",
            currentHUDSelectionId: nil,
            lastActiveAppId: nil,
            isHUDVisible: false
        )

        XCTAssertEqual(next, "com.google.Chrome-200")
    }

    func testCompositeIdsHUDCycling() {
        // HUD visible, cycling through multi-instance items
        let items = makeItems(["com.google.Chrome-100", "com.google.Chrome-200", "com.app.B-300"])

        // HUD shows Chrome-200, expect next is B-300
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.google.Chrome-100",
            currentHUDSelectionId: "com.google.Chrome-200",
            lastActiveAppId: nil,
            isHUDVisible: true
        )

        XCTAssertEqual(next, "com.app.B-300")
    }

    func testCompositeIdsWrapAround() {
        let items = makeItems(["com.google.Chrome-100", "com.google.Chrome-200"])

        // HUD shows last item, expect wrap to first
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: nil,
            currentHUDSelectionId: "com.google.Chrome-200",
            lastActiveAppId: nil,
            isHUDVisible: true
        )

        XCTAssertEqual(next, "com.google.Chrome-100")
    }

    func testResolvedLastActiveIdMatchesCompositeItem() {
        // Simulates the caller resolving a stored plain bundle ID to a composite ID
        // before calling nextAppId (as AppSwitcher now does)
        let items = makeItems(["com.google.Chrome-500", "com.app.B-600"])

        // lastActiveAppId has been pre-resolved to the composite ID by the caller
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder", // Not in group
            currentHUDSelectionId: nil,
            lastActiveAppId: "com.google.Chrome-500", // Resolved composite ID
            isHUDVisible: false
        )

        // Should resume to last active (Chrome instance)
        XCTAssertEqual(next, "com.google.Chrome-500")
    }

    func testUnresolvedPlainBundleIdFallsToFirst() {
        // If lastActiveAppId is a plain bundle ID that doesn't match any composite item,
        // the cycling logic should fall through to the first item
        let items = makeItems(["com.google.Chrome-500", "com.app.B-600"])

        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder",
            currentHUDSelectionId: nil,
            lastActiveAppId: "com.google.Chrome", // Plain ID, won't match composite
            isHUDVisible: false
        )

        // Falls through to first item since no match
        XCTAssertEqual(next, "com.google.Chrome-500")
    }
}

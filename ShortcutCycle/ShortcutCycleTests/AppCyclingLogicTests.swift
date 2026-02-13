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

    // MARK: - Multi-Instance Last Active Regression Tests

    func testCompositeLastActiveIdReturnsCorrectInstance() {
        // Regression test: with 3 instances of the same app (e.g., Firefox profiles A, B, C),
        // if the user was on instance C (PID 300) and switched away, the shortcut should
        // return to C, not A (the first by PID).
        let items = makeItems([
            "org.mozilla.firefox-100",  // Profile A
            "org.mozilla.firefox-200",  // Profile B
            "org.mozilla.firefox-300"   // Profile C
        ])

        // User was on profile C, switched to Finder, now hits shortcut
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder-999",
            currentHUDSelectionId: nil,
            lastActiveAppId: "org.mozilla.firefox-300", // Composite ID for profile C
            isHUDVisible: false
        )

        // Should return to profile C (last active), not profile A
        XCTAssertEqual(next, "org.mozilla.firefox-300")
    }

    func testCompositeLastActiveIdMiddleInstance() {
        // Same regression test but for the middle instance
        let items = makeItems([
            "org.mozilla.firefox-100",  // Profile A
            "org.mozilla.firefox-200",  // Profile B
            "org.mozilla.firefox-300"   // Profile C
        ])

        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder-999",
            currentHUDSelectionId: nil,
            lastActiveAppId: "org.mozilla.firefox-200", // Profile B
            isHUDVisible: false
        )

        XCTAssertEqual(next, "org.mozilla.firefox-200")
    }

    // MARK: - resolveLastActiveId Tests

    func makeResolvable(_ pairs: [(id: String, bundleId: String)]) -> [ResolvableAppItem] {
        pairs.map { ResolvableAppItem(id: $0.id, bundleId: $0.bundleId) }
    }

    func testResolveNilStoredId() {
        let items = makeResolvable([
            (id: "org.mozilla.firefox-100", bundleId: "org.mozilla.firefox")
        ])
        XCTAssertNil(AppCyclingLogic.resolveLastActiveId(storedId: nil, items: items))
    }

    func testResolveExactCompositeMatch() {
        // Stored composite ID matches a running instance exactly
        let items = makeResolvable([
            (id: "org.mozilla.firefox-100", bundleId: "org.mozilla.firefox"),
            (id: "org.mozilla.firefox-200", bundleId: "org.mozilla.firefox"),
            (id: "org.mozilla.firefox-300", bundleId: "org.mozilla.firefox")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox-300",
            items: items
        )
        // Must return the exact instance, not the first one
        XCTAssertEqual(resolved, "org.mozilla.firefox-300")
    }

    func testResolvePlainBundleIdBackwardCompat() {
        // Old stored plain bundle ID resolves to the first instance (backward compat)
        let items = makeResolvable([
            (id: "org.mozilla.firefox-100", bundleId: "org.mozilla.firefox"),
            (id: "org.mozilla.firefox-200", bundleId: "org.mozilla.firefox")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox",
            items: items
        )
        XCTAssertEqual(resolved, "org.mozilla.firefox-100")
    }

    func testResolveProfileClosedFallsBackToFirstRemaining() {
        // Profile C (PID 300) was last active but is now closed.
        // A (100) and B (200) are still running. Should fall back to first remaining.
        let items = makeResolvable([
            (id: "org.mozilla.firefox-100", bundleId: "org.mozilla.firefox"),
            (id: "org.mozilla.firefox-200", bundleId: "org.mozilla.firefox")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox-300",
            items: items
        )
        // PID 300 doesn't exist; prefix fallback matches first Firefox instance
        XCTAssertEqual(resolved, "org.mozilla.firefox-100")
    }

    func testResolveAllClosedNewInstanceCreated() {
        // All old Firefox instances closed, new profile D (PID 400) appeared
        let items = makeResolvable([
            (id: "org.mozilla.firefox-400", bundleId: "org.mozilla.firefox")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox-300",
            items: items
        )
        // Prefix fallback finds the new instance
        XCTAssertEqual(resolved, "org.mozilla.firefox-400")
    }

    func testResolveAllInstancesClosedDifferentAppRunning() {
        // All Firefox instances closed, only Chrome is running
        let items = makeResolvable([
            (id: "com.google.Chrome-500", bundleId: "com.google.Chrome")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox-300",
            items: items
        )
        // No Firefox instances at all — returns nil
        XCTAssertNil(resolved)
    }

    func testResolveNonRunningAppInOpenIfNeededMode() {
        // "Open App If Needed" mode: Firefox not running shows as plain bundle ID item
        let items = makeResolvable([
            (id: "org.mozilla.firefox", bundleId: "org.mozilla.firefox"),  // not running
            (id: "com.google.Chrome-500", bundleId: "com.google.Chrome")  // running
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox-300",
            items: items
        )
        // Prefix fallback: "org.mozilla.firefox-300" starts with "org.mozilla.firefox-"
        // matches the non-running Firefox item, which is correct — it will trigger a launch
        XCTAssertEqual(resolved, "org.mozilla.firefox")
    }

    func testResolveEmptyItems() {
        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox-300",
            items: []
        )
        XCTAssertNil(resolved)
    }

    func testResolveDoesNotCrossMatchDifferentApps() {
        // Ensure "com.app.foo-100" doesn't match "com.app.foobar" via prefix
        let items = makeResolvable([
            (id: "com.app.foobar-200", bundleId: "com.app.foobar")
        ])

        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "com.app.foo-100",
            items: items
        )
        // "com.app.foo-100" does NOT start with "com.app.foobar-"
        XCTAssertNil(resolved)
    }

    // MARK: - End-to-End Edge Case Tests (resolve + nextAppId)

    func testEndToEndProfileClosedActivatesFirstRemaining() {
        // Profile C closed, A and B still running, user is on Finder
        let resolvable = makeResolvable([
            (id: "org.mozilla.firefox-100", bundleId: "org.mozilla.firefox"),
            (id: "org.mozilla.firefox-200", bundleId: "org.mozilla.firefox")
        ])
        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox-300", items: resolvable
        )
        // Falls back to first Firefox instance
        XCTAssertEqual(resolved, "org.mozilla.firefox-100")

        let items = makeItems(["org.mozilla.firefox-100", "org.mozilla.firefox-200"])
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder-999",
            currentHUDSelectionId: nil,
            lastActiveAppId: resolved,
            isHUDVisible: false
        )
        // Activates profile A (first remaining Firefox instance)
        XCTAssertEqual(next, "org.mozilla.firefox-100")
    }

    func testEndToEndAllClosedNewProfileActivatesIt() {
        // All old Firefox gone, new profile D appeared, group also has Chrome
        let resolvable = makeResolvable([
            (id: "org.mozilla.firefox-400", bundleId: "org.mozilla.firefox"),
            (id: "com.google.Chrome-500", bundleId: "com.google.Chrome")
        ])
        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox-300", items: resolvable
        )
        XCTAssertEqual(resolved, "org.mozilla.firefox-400")

        let items = makeItems(["org.mozilla.firefox-400", "com.google.Chrome-500"])
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder-999",
            currentHUDSelectionId: nil,
            lastActiveAppId: resolved,
            isHUDVisible: false
        )
        // Activates the new Firefox instance (stays with Firefox, not Chrome)
        XCTAssertEqual(next, "org.mozilla.firefox-400")
    }

    func testEndToEndAllFirefoxClosedFallsToNextApp() {
        // Firefox completely gone, only Chrome running
        let resolvable = makeResolvable([
            (id: "com.google.Chrome-500", bundleId: "com.google.Chrome")
        ])
        let resolved = AppCyclingLogic.resolveLastActiveId(
            storedId: "org.mozilla.firefox-300", items: resolvable
        )
        XCTAssertNil(resolved)

        let items = makeItems(["com.google.Chrome-500"])
        let next = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.apple.finder-999",
            currentHUDSelectionId: nil,
            lastActiveAppId: resolved,
            isHUDVisible: false
        )
        // No Firefox at all — falls through to first item (Chrome)
        XCTAssertEqual(next, "com.google.Chrome-500")
    }
}

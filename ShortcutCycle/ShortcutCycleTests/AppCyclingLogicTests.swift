import XCTest
import Foundation
@testable import ShortcutCycle

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
}

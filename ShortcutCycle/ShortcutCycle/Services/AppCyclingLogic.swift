import Foundation

/// Represents an item that can be cycled through
public struct CyclingAppItem: Identifiable, Equatable {
    public let id: String
    
    public init(id: String) {
        self.id = id
    }
}

public enum AppCyclingLogic {
    /// Determines the next app ID to switch to
    /// - Parameters:
    ///   - items: List of available apps to cycle through
    ///   - currentFrontmostAppId: The bundle ID of the currently frontmost app
    ///   - currentHUDSelectionId: The bundle ID currently selected in the HUD (if visible)
    ///   - lastActiveAppId: The bundle ID of the last active app in this group
    ///   - isHUDVisible: Whether the HUD is currently visible
    /// - Returns: The bundle ID of the next app to activate
    public static func nextAppId(
        items: [CyclingAppItem],
        currentFrontmostAppId: String?,
        currentHUDSelectionId: String?,
        lastActiveAppId: String?,
        isHUDVisible: Bool
    ) -> String {
        guard !items.isEmpty else {
            // Fallback if no items (should not happen in caller, but safe)
            return "" 
        }
        
        // 1. If HUD is already visible, we are interacting with the list.
        // Cycle from the currently selected item in the HUD.
        if isHUDVisible, let currentID = currentHUDSelectionId {
            if let currentIndex = items.firstIndex(where: { $0.id == currentID }) {
                let nextIndex = (currentIndex + 1) % items.count
                return items[nextIndex].id
            } else {
                // Current selection not in items (e.g. closed?), restart from 0
                return items[0].id
            }
        }
        
        // 2. HUD is NOT visible. This is a new cycle start.
        
        // Check if the frontmost app is part of our group
        if let frontmostID = currentFrontmostAppId,
           let currentIndex = items.firstIndex(where: { $0.id == frontmostID }) {
            // We are gathering "speed" from the current app. Go to next.
            let nextIndex = (currentIndex + 1) % items.count
            return items[nextIndex].id
        }
        
        // 3. Frontmost app is NOT in the group (or we are not in it).
        // Use the last active app for this group if available.
        if let lastID = lastActiveAppId,
           items.contains(where: { $0.id == lastID }) {
            return lastID
        }
        
        // 4. Default to first item
        return items[0].id
    }
}

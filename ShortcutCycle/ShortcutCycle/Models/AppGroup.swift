import Foundation
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Represents a group of applications with a shared keyboard shortcut
public struct AppGroup: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var apps: [AppItem]
    public var lastActiveAppBundleId: String?
    public var isEnabled: Bool = true
    public var lastModified: Date = Date()
    public var openAppIfNeeded: Bool?
    public var mruOrder: [String]?

    public var shouldOpenAppIfNeeded: Bool {
        openAppIfNeeded ?? false
    }
    
    // Legacy property for migration - will be ignored after first load
    // This allows old data to be decoded without crashing
    private var shortcut: LegacyKeyboardShortcutData?
    
    public init(id: UUID = UUID(), name: String, apps: [AppItem] = [], isEnabled: Bool = true, openAppIfNeeded: Bool? = nil, mruOrder: [String]? = nil, lastModified: Date = Date()) {
        self.id = id
        self.name = name
        self.apps = apps
        self.isEnabled = isEnabled
        self.openAppIfNeeded = openAppIfNeeded
        self.mruOrder = mruOrder
        self.lastModified = lastModified
    }
    
    public mutating func addApp(_ app: AppItem) {
        if !apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            apps.append(app)
            lastModified = Date()
        }
    }
    
    public mutating func removeApp(_ app: AppItem) {
        apps.removeAll { $0.id == app.id }
        lastModified = Date()
    }
    
    public mutating func moveApp(from source: IndexSet, to destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
        lastModified = Date()
    }
    
    /// Get the KeyboardShortcuts.Name for this group
    public var shortcutName: KeyboardShortcuts.Name {
        .forGroup(id)
    }
}

/// Legacy struct for backward compatibility during migration
/// This allows the app to read old data without crashing
private struct LegacyKeyboardShortcutData: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

// MARK: - MainActor helper for shortcut access
public extension AppGroup {
    /// Check if this group has a shortcut assigned (must be called from main actor)
    @MainActor
    var hasShortcut: Bool {
        KeyboardShortcuts.getShortcut(for: shortcutName) != nil
    }
    
    /// Get the display string for the current shortcut (if any) - must be called from main actor
    @MainActor
    var shortcutDisplayString: String? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: shortcutName) else {
            return nil
        }
        return shortcut.description
    }
}

// MARK: - Notification Names
public extension Notification.Name {
    /// Posted when groups or shortcuts have changed and need re-registration
    static let shortcutsNeedUpdate = Notification.Name("ShortcutsNeedUpdate")
}

// MARK: - App Cycling Logic

/// Represents an item that can be cycled through
public struct CyclingAppItem: Identifiable, Equatable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

/// Represents an item with both its composite ID and plain bundle ID,
/// used to resolve a stored last-active ID back to a current running item.
public struct ResolvableAppItem {
    public let id: String
    public let bundleId: String

    public init(id: String, bundleId: String) {
        self.id = id
        self.bundleId = bundleId
    }
}

public enum AppCyclingLogic {

    /// Resolves a stored last-active ID to a current item's composite ID.
    ///
    /// The stored ID may be a composite ID ("bundleId::pid"), a plain bundle ID,
    /// or nil. Resolution uses a 3-tier strategy:
    /// 1. Exact match on composite ID (e.g. stored "firefox::300" matches item with id "firefox::300")
    /// 2. Plain bundle ID match (e.g. stored "firefox" matches item with bundleId "firefox")
    /// 3. Prefix fallback for stale PIDs (e.g. stored "firefox::300" matches item with bundleId "firefox"
    ///    when PID 300 no longer exists but other instances are running)
    public static func resolveLastActiveId(
        storedId: String?,
        items: [ResolvableAppItem]
    ) -> String? {
        guard let storedId = storedId else { return nil }

        // 1. Exact match on composite ID or plain bundle ID
        if let match = items.first(where: {
            $0.id == storedId || $0.bundleId == storedId
        }) {
            return match.id
        }

        // 2. Fallback: stored composite ID whose PID no longer exists —
        //    match by bundle ID prefix to find another instance of the same app
        return items.first(where: {
            storedId.hasPrefix($0.bundleId + "::")
        })?.id
    }
    /// Determines the next app ID to switch to
    /// - Parameters:
    ///   - items: List of available apps to cycle through
    ///   - currentFrontmostAppId: The bundle ID of the currently frontmost app
    ///   - currentHUDSelectionId: The bundle ID currently selected in the HUD (if visible)
    ///   - lastActiveAppId: The bundle ID of the last active app in this group
    ///   - isHUDVisible: Whether the HUD is currently visible
    ///   - prioritizeFrontmost: Whether a new cycle should advance from current frontmost app
    /// - Returns: The bundle ID of the next app to activate
    public static func nextAppId(
        items: [CyclingAppItem],
        currentFrontmostAppId: String?,
        currentHUDSelectionId: String?,
        lastActiveAppId: String?,
        isHUDVisible: Bool,
        prioritizeFrontmost: Bool = true
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
        if prioritizeFrontmost {
            if let frontmostID = currentFrontmostAppId,
               let currentIndex = items.firstIndex(where: { $0.id == frontmostID }) {
                // We are gathering "speed" from the current app. Go to next.
                let nextIndex = (currentIndex + 1) % items.count
                return items[nextIndex].id
            }
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

    // MARK: - MRU (Most Recently Used) Ordering

    /// Returns indices that reorder items by MRU (most recently used) order.
    /// Uses 3-tier matching per item: exact composite ID, plain bundle ID, bundle prefix.
    /// Items not in mruOrder maintain their original relative order at the end.
    public static func sortedByMRU(
        itemIds: [String],
        itemBundleIds: [String],
        mruOrder: [String]?,
        groupBundleIds: [String]
    ) -> [Int] {
        guard let mruOrder = mruOrder, !mruOrder.isEmpty else {
            return Array(itemIds.indices)
        }

        // Build rank map for MRU entries (lower = more recent)
        var mruRank: [String: Int] = [:]
        for (i, entry) in mruOrder.enumerated() {
            mruRank[entry] = i
        }

        // Assign ranks to non-MRU items based on group order (after all MRU items)
        let offset = mruOrder.count
        var groupRank: [String: Int] = [:]
        for (i, bundleId) in groupBundleIds.enumerated() {
            if groupRank[bundleId] == nil {
                groupRank[bundleId] = offset + i
            }
        }

        let fallback = offset + groupBundleIds.count

        // 3-tier ranking for each item
        let ranks: [Int] = itemIds.indices.map { i in
            let itemId = itemIds[i]
            let bundleId = itemBundleIds[i]

            // Tier 1: Exact match on composite ID
            if let r = mruRank[itemId] { return r }

            // Tier 2: Exact match on plain bundle ID (backward compat)
            if let r = mruRank[bundleId] { return r }

            // Tier 3: Bundle ID prefix match (stale PID fallback)
            let prefix = bundleId + "::"
            for (idx, entry) in mruOrder.enumerated() {
                if entry.hasPrefix(prefix) {
                    return idx
                }
            }

            // Tier 4: Group order fallback
            return groupRank[bundleId, default: fallback]
        }

        return itemIds.indices.sorted { a, b in
            if ranks[a] != ranks[b] {
                return ranks[a] < ranks[b]
            }
            // Same rank — preserve original order
            return a < b
        }
    }

    /// Returns an updated MRU order with the activated item moved to front.
    /// Accepts composite ID (e.g. "bundleId::pid") and plain bundle ID.
    /// Upgrades old plain entries to composite. Filters by validBundleIds
    /// and liveItemIds to evict stale PID entries that no longer correspond
    /// to any running instance.
    public static func updatedMRUOrder(
        currentOrder: [String]?,
        activatedId: String,
        activatedBundleId: String,
        validBundleIds: Set<String>,
        liveItemIds: Set<String>
    ) -> [String] {
        var order = currentOrder ?? []

        // Remove exact composite ID
        order.removeAll { $0 == activatedId }

        // Remove plain bundle ID (upgrade old plain entries to composite)
        if activatedId != activatedBundleId {
            order.removeAll { $0 == activatedBundleId }
        }

        // Insert composite ID at front
        order.insert(activatedId, at: 0)

        // Filter: keep entries that match a live HUD item ID,
        // or plain bundle IDs still in the group. Stale composite IDs
        // (PIDs that no longer exist) are evicted.
        return order.filter { entry in
            if liveItemIds.contains(entry) { return true }
            if validBundleIds.contains(entry) { return true }
            return false
        }
    }
}

public struct CycleSessionState: Equatable {
    public let groupId: UUID
    public let cycleOrder: [String]
    public let lastSelectedId: String
    public let updatedAt: Date

    public init(groupId: UUID, cycleOrder: [String], lastSelectedId: String, updatedAt: Date) {
        self.groupId = groupId
        self.cycleOrder = cycleOrder
        self.lastSelectedId = lastSelectedId
        self.updatedAt = updatedAt
    }
}

public enum CycleSessionLogic {
    /// Returns the next item ID for blind-tap cycling and the updated session state.
    /// - Note: HUD-visible interactions bypass session logic and reset state to avoid
    ///   conflicts with HUD's own selection progression.
    public static func nextId(
        state: CycleSessionState?,
        groupId: UUID,
        currentItemIds: [String],
        fallbackNextId: String,
        useSession: Bool = true,
        isHUDVisible: Bool,
        now: Date,
        timeout: TimeInterval
    ) -> (nextId: String, nextState: CycleSessionState?) {
        guard useSession else {
            return (fallbackNextId, nil)
        }
        guard !isHUDVisible else {
            return (fallbackNextId, nil)
        }
        guard !currentItemIds.isEmpty else {
            return (fallbackNextId, nil)
        }

        if let state = state,
           state.groupId == groupId,
           now.timeIntervalSince(state.updatedAt) <= timeout,
           let continuedId = continuedIdFromSession(state: state, currentItemIds: currentItemIds) {
            return (
                continuedId,
                CycleSessionState(
                    groupId: groupId,
                    cycleOrder: state.cycleOrder,
                    lastSelectedId: continuedId,
                    updatedAt: now
                )
            )
        }

        // Start a fresh short-lived session from the current order.
        return (
            fallbackNextId,
            CycleSessionState(
                groupId: groupId,
                cycleOrder: currentItemIds,
                lastSelectedId: fallbackNextId,
                updatedAt: now
            )
        )
    }

    private static func continuedIdFromSession(state: CycleSessionState, currentItemIds: [String]) -> String? {
        let available = Set(currentItemIds)
        let order = state.cycleOrder
        guard !order.isEmpty else { return nil }

        if let lastIndex = order.firstIndex(of: state.lastSelectedId) {
            for step in 1...order.count {
                let index = (lastIndex + step) % order.count
                let candidate = order[index]
                if available.contains(candidate) {
                    return candidate
                }
            }
            return nil
        }

        // Last selected item no longer exists in session order; pick first available
        // in that original order to preserve predictable progression.
        return order.first(where: { available.contains($0) })
    }
}

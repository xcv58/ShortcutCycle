import Foundation

/// Pure filtering logic for HUD app items.
/// Extracted into Core so it can be unit-tested with injectable dependencies.
public enum HUDItemFilter {
    /// Filter a list of HUD items for multi-profile apps.
    ///
    /// Rules:
    /// - Single-instance apps (or items without a PID) are always kept.
    /// - For multi-instance (multi-profile) apps:
    ///   - Hidden apps (Cmd+H, `isHidden==true`) are kept — `unhide()+activate()` reliably restores them.
    ///   - Apps with visible on-screen windows are kept.
    ///   - Minimized apps (not hidden, no on-screen windows) are filtered out.
    ///   - If ALL instances are minimized, one is kept so the app doesn't vanish from the HUD.
    ///
    /// - Parameters:
    ///   - items: Input items (may contain multiple instances of the same bundle ID).
    ///   - isHidden: Returns `true` if the process is hidden (Cmd+H). Receives PID.
    ///   - hasVisibleWindows: Returns `true` if the process has at least one on-screen window. Receives PID.
    /// - Returns: Filtered item list preserving relative order.
    public static func filter(
        _ items: [HUDAppItem],
        isHidden: (pid_t) -> Bool,
        hasVisibleWindows: (pid_t) -> Bool
    ) -> [HUDAppItem] {
        let itemsByBundleId = Dictionary(grouping: items, by: { $0.bundleId })
        var result = items.filter { item in
            guard let pid = item.pid, itemsByBundleId[item.bundleId, default: []].count > 1 else {
                return true
            }
            if isHidden(pid) { return true }
            return hasVisibleWindows(pid)
        }
        // Fallback: if all instances of a multi-profile app were filtered, keep the first
        for (bundleId, originals) in itemsByBundleId where originals.count > 1 {
            if !result.contains(where: { $0.bundleId == bundleId }), let first = originals.first {
                result.append(first)
            }
        }
        return result
    }
}

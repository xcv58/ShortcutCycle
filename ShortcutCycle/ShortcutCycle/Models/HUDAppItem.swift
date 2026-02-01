import Foundation
import AppKit

/// Common app item used in HUD
struct HUDAppItem: Identifiable, Equatable {
    let id: String // Bundle ID
    let name: String
    let icon: NSImage?
    let isRunning: Bool
    
    // For Equatable
    static func == (lhs: HUDAppItem, rhs: HUDAppItem) -> Bool {
        lhs.id == rhs.id
    }
}

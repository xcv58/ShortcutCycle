import Foundation
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

@MainActor
struct WelcomePresentationState {
    private(set) var activeRequestID: UUID?

    var isShowingCallout: Bool {
        activeRequestID != nil
    }

    @discardableResult
    mutating func consumePendingRequest(_ requestID: UUID?) -> String? {
        guard let requestID else { return nil }
        activeRequestID = requestID
        return URLSettingsTab.groups.rawValue
    }

    mutating func dismiss() {
        activeRequestID = nil
    }

    mutating func endWindowSession() {
        activeRequestID = nil
    }
}

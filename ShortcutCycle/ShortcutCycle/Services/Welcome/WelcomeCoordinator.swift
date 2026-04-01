import Foundation
import Combine

// MARK: - Welcome Coordinator

/// Owns first-launch persistence and queues one transient welcome presentation
/// request at a time. Use `WelcomeCoordinator.shared` at app scope.
@MainActor
final class WelcomeCoordinator: ObservableObject {

    // MARK: Constants

    static let hasSeenWelcomeKey = "hasSeenWelcomeOnFirstLaunch"

    // MARK: Shared Instance

    static let shared = WelcomeCoordinator()

    // MARK: Published State

    /// Non-nil when a welcome presentation has been queued but not yet consumed.
    @Published private(set) var pendingRequestID: UUID?

    // MARK: Private

    private let userDefaults: UserDefaults

    // MARK: Init

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - API

    /// Called at app launch. Marks the welcome as seen and returns a request ID
    /// if this is the first manual launch. Returns `nil` on subsequent launches.
    @discardableResult
    func prepareAutomaticWelcomeIfNeeded() -> UUID? {
        guard !userDefaults.bool(forKey: Self.hasSeenWelcomeKey) else { return nil }
        userDefaults.set(true, forKey: Self.hasSeenWelcomeKey)
        let requestID = UUID()
        pendingRequestID = requestID
        return requestID
    }

    /// Queues a new welcome request for manual replay. Does not reset the
    /// "seen" flag — future launches remain unaffected.
    @discardableResult
    func requestReplay() -> UUID {
        let requestID = UUID()
        pendingRequestID = requestID
        return requestID
    }

    /// Clears `pendingRequestID` when the Settings window has consumed the
    /// request identified by `requestID`. Ignores mismatched IDs.
    func markRequestHandled(_ requestID: UUID) {
        guard pendingRequestID == requestID else { return }
        pendingRequestID = nil
    }
}

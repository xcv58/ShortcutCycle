import XCTest
@testable import ShortcutCycle

@MainActor
final class WelcomeCoordinatorTests: XCTestCase {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testPrepareAutomaticWelcomeMarksSeenAndQueuesRequest() {
        let suite = "WelcomeCoordinatorTests.prepareAutomatic.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let coordinator = WelcomeCoordinator(userDefaults: defaults)
        let requestID = coordinator.prepareAutomaticWelcomeIfNeeded()

        XCTAssertNotNil(requestID)
        XCTAssertTrue(defaults.bool(forKey: WelcomeCoordinator.hasSeenWelcomeKey))
        XCTAssertEqual(coordinator.pendingRequestID, requestID)
    }

    func testPrepareAutomaticWelcomeOnlyQueuesOnce() {
        let suite = "WelcomeCoordinatorTests.onlyOnce.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let coordinator = WelcomeCoordinator(userDefaults: defaults)
        _ = coordinator.prepareAutomaticWelcomeIfNeeded()
        let secondRequest = coordinator.prepareAutomaticWelcomeIfNeeded()

        XCTAssertNil(secondRequest)
    }

    func testPrepareAutomaticWelcomeSkipsWhenAlreadySeen() {
        let suite = "WelcomeCoordinatorTests.alreadySeen.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defaults.set(true, forKey: WelcomeCoordinator.hasSeenWelcomeKey)
        defer { defaults.removePersistentDomain(forName: suite) }

        let coordinator = WelcomeCoordinator(userDefaults: defaults)
        let requestID = coordinator.prepareAutomaticWelcomeIfNeeded()

        XCTAssertNil(requestID)
        XCTAssertNil(coordinator.pendingRequestID)
    }

    func testMarkRequestHandledClearsMatchingPendingRequest() {
        let suite = "WelcomeCoordinatorTests.markHandled.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let coordinator = WelcomeCoordinator(userDefaults: defaults)
        let requestID = coordinator.prepareAutomaticWelcomeIfNeeded()!
        coordinator.markRequestHandled(requestID)

        XCTAssertNil(coordinator.pendingRequestID)
    }

    func testMarkRequestHandledIgnoresMismatchedID() {
        let suite = "WelcomeCoordinatorTests.mismatch.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let coordinator = WelcomeCoordinator(userDefaults: defaults)
        let requestID = coordinator.prepareAutomaticWelcomeIfNeeded()!
        coordinator.markRequestHandled(UUID()) // different ID

        XCTAssertEqual(coordinator.pendingRequestID, requestID)
    }

    func testManualReplayQueuesNewRequestWithoutResettingSeenFlag() {
        let suite = "WelcomeCoordinatorTests.manualReplay.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let coordinator = WelcomeCoordinator(userDefaults: defaults)
        _ = coordinator.prepareAutomaticWelcomeIfNeeded()
        let replayRequestID = coordinator.requestReplay()

        XCTAssertEqual(coordinator.pendingRequestID, replayRequestID)
        XCTAssertTrue(defaults.bool(forKey: WelcomeCoordinator.hasSeenWelcomeKey))
    }

    func testManualReplayCanTriggerEvenWithoutPriorAutomatic() {
        let suite = "WelcomeCoordinatorTests.replayWithoutAutomatic.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let coordinator = WelcomeCoordinator(userDefaults: defaults)
        let replayRequestID = coordinator.requestReplay()

        XCTAssertNotNil(replayRequestID)
        XCTAssertEqual(coordinator.pendingRequestID, replayRequestID)
    }
}

import XCTest
@testable import ShortcutCycle

final class WelcomeExperiencePolicyTests: XCTestCase {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testBannerIsShownUntilExplicitDismissal() {
        XCTAssertTrue(
            WelcomeExperiencePolicy.shouldShowBanner(hasDismissedWelcome: false)
        )
        XCTAssertFalse(
            WelcomeExperiencePolicy.shouldShowBanner(hasDismissedWelcome: true)
        )
    }

    func testReplayControlAppearsOnlyAfterDismissal() {
        XCTAssertFalse(
            WelcomeExperiencePolicy.shouldShowReplayControl(hasDismissedWelcome: false)
        )
        XCTAssertTrue(
            WelcomeExperiencePolicy.shouldShowReplayControl(hasDismissedWelcome: true)
        )
    }

    func testPrepareReplayClearsDismissedWelcomeFlag() {
        let suite = "WelcomeExperiencePolicyTests.prepareReplay.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defaults.set(true, forKey: WelcomeExperiencePolicy.hasDismissedWelcomeKey)
        defer { defaults.removePersistentDomain(forName: suite) }

        WelcomeExperiencePolicy.prepareReplay(userDefaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: WelcomeExperiencePolicy.hasDismissedWelcomeKey))
    }

    func testShouldAutoOpenSettingsOnFirstManualLaunchWhenNotPreviouslyOpened() {
        XCTAssertTrue(
            WelcomeExperiencePolicy.shouldAutoOpenSettingsOnFirstManualLaunch(
                hasAutoOpenedWelcomeSettings: false,
                suppressForCurrentLaunch: false
            )
        )
    }

    func testDoesNotAutoOpenSettingsAfterFirstAutomaticOpen() {
        XCTAssertFalse(
            WelcomeExperiencePolicy.shouldAutoOpenSettingsOnFirstManualLaunch(
                hasAutoOpenedWelcomeSettings: true,
                suppressForCurrentLaunch: false
            )
        )
    }

    func testDoesNotAutoOpenSettingsWhenCurrentLaunchWasExternallyTriggered() {
        XCTAssertFalse(
            WelcomeExperiencePolicy.shouldAutoOpenSettingsOnFirstManualLaunch(
                hasAutoOpenedWelcomeSettings: false,
                suppressForCurrentLaunch: true
            )
        )
    }
}

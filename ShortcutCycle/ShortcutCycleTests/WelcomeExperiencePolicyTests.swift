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

    func testPrepareAutomaticSettingsOpenReturnsTrueAndSetsFlag() {
        let suite = "WelcomeExperiencePolicyTests.prepareAutoOpen.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let result = WelcomeExperiencePolicy.prepareAutomaticSettingsOpenIfNeeded(
            userDefaults: defaults,
            suppressForCurrentLaunch: false
        )

        XCTAssertTrue(result, "Should return true on first call (not yet opened)")
        XCTAssertTrue(
            defaults.bool(forKey: WelcomeExperiencePolicy.hasAutoOpenedWelcomeSettingsKey),
            "Should persist the flag so subsequent launches do not auto-open again"
        )
    }

    func testPrepareAutomaticSettingsOpenReturnsFalseOnSubsequentCall() {
        let suite = "WelcomeExperiencePolicyTests.prepareAutoOpenRepeat.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        _ = WelcomeExperiencePolicy.prepareAutomaticSettingsOpenIfNeeded(
            userDefaults: defaults,
            suppressForCurrentLaunch: false
        )
        let result = WelcomeExperiencePolicy.prepareAutomaticSettingsOpenIfNeeded(
            userDefaults: defaults,
            suppressForCurrentLaunch: false
        )

        XCTAssertFalse(result, "Should return false after the flag is already set")
    }

    func testPrepareAutomaticSettingsOpenReturnsFalseWhenSuppressed() {
        let suite = "WelcomeExperiencePolicyTests.prepareAutoOpenSuppressed.\(UUID().uuidString)"
        let defaults = makeDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let result = WelcomeExperiencePolicy.prepareAutomaticSettingsOpenIfNeeded(
            userDefaults: defaults,
            suppressForCurrentLaunch: true
        )

        XCTAssertFalse(result, "Should return false when suppressed")
        XCTAssertFalse(
            defaults.bool(forKey: WelcomeExperiencePolicy.hasAutoOpenedWelcomeSettingsKey),
            "Suppressed call should not set the flag"
        )
    }

}

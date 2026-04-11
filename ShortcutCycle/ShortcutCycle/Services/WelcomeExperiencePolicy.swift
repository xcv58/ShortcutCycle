import Foundation

// MARK: - Welcome Experience Policy

/// Centralizes all first-launch and welcome-replay business rules.
enum WelcomeExperiencePolicy {
    static let hasDismissedWelcomeKey = "hasDismissedWelcome"
    static let hasAutoOpenedWelcomeSettingsKey = "hasAutoOpenedWelcomeSettings"
    static var isScreenshotModeEnabled = false

    static func shouldShowBanner(hasDismissedWelcome: Bool) -> Bool {
        guard !isScreenshotModeEnabled else { return false }
        return !hasDismissedWelcome
    }

    static func shouldShowReplayControl(hasDismissedWelcome: Bool) -> Bool {
        guard !isScreenshotModeEnabled else { return false }
        return hasDismissedWelcome
    }

    /// Resets the banner-dismissed flag so the welcome banner reappears on the next
    /// Settings window open. Intentionally does not reset `hasAutoOpenedWelcomeSettingsKey`:
    /// replay shows the banner again but does not re-trigger the automatic Settings open
    /// on the next cold launch.
    static func prepareReplay(userDefaults: UserDefaults = .standard) {
        userDefaults.set(false, forKey: hasDismissedWelcomeKey)
    }

    static func shouldAutoOpenSettingsOnFirstManualLaunch(
        hasAutoOpenedWelcomeSettings: Bool,
        suppressForCurrentLaunch: Bool
    ) -> Bool {
        !hasAutoOpenedWelcomeSettings && !suppressForCurrentLaunch
    }

    @discardableResult
    static func prepareAutomaticSettingsOpenIfNeeded(
        userDefaults: UserDefaults = .standard,
        suppressForCurrentLaunch: Bool
    ) -> Bool {
        let hasAutoOpened = userDefaults.bool(forKey: hasAutoOpenedWelcomeSettingsKey)
        guard shouldAutoOpenSettingsOnFirstManualLaunch(
            hasAutoOpenedWelcomeSettings: hasAutoOpened,
            suppressForCurrentLaunch: suppressForCurrentLaunch
        ) else {
            return false
        }

        userDefaults.set(true, forKey: hasAutoOpenedWelcomeSettingsKey)
        return true
    }
}

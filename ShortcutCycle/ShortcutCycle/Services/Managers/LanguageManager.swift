import Foundation
import Combine

/// Publishes changes when the system locale changes, so SwiftUI views can re-render.
class LocaleObserver: ObservableObject {
    @Published var id: UUID = UUID()

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localeDidChange),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )
    }

    @objc private func localeDidChange() {
        DispatchQueue.main.async {
            self.id = UUID()
        }
    }
}

class LanguageManager {
    static let shared = LanguageManager()
    
    struct Language {
        let code: String
        let name: String

        /// Returns a display string showing both the system-localized name and the native name.
        /// e.g. "German / Deutsch" when the system language is English.
        /// If both names are the same, returns just the native name.
        func displayName(in locale: Locale = .current) -> String {
            let localizedName = locale.localizedString(forIdentifier: code)?.localizedCapitalized ?? name
            if localizedName.caseInsensitiveCompare(name) == .orderedSame {
                return name
            }
            return "\(localizedName) / \(name)"
        }
    }
    
    let supportedLanguages = [
        Language(code: "en", name: "English"),
        Language(code: "de", name: "Deutsch"),
        Language(code: "fr", name: "Français"),
        Language(code: "es", name: "Español"),
        Language(code: "ja", name: "日本語"),
        Language(code: "pt-BR", name: "Português (Brasil)"),
        Language(code: "zh-Hans", name: "简体中文"),
        Language(code: "zh-Hant", name: "繁體中文"),
        Language(code: "it", name: "Italiano"),
        Language(code: "ko", name: "한국어"),
        Language(code: "ar", name: "العربية"),
        Language(code: "nl", name: "Nederlands"),
        Language(code: "pl", name: "Polski"),
        Language(code: "tr", name: "Türkçe"),
        Language(code: "ru", name: "Русский")
    ]
    
    /// The best-matching language code from the user's system language preferences,
    /// matched against our supported languages using Apple's BCP 47 matching.
    /// e.g. system language "zh-Hans-US" correctly matches "zh-Hans" (not just "zh").
    ///
    /// Reads directly from global system preferences to avoid the per-app
    /// AppleLanguages override that macOS sets based on CFBundleLocalizations.
    var systemLanguageCode: String {
        let availableCodes = supportedLanguages.map { $0.code }
        let systemLanguages = Self.globalPreferredLanguages
        let preferred = Bundle.preferredLocalizations(from: availableCodes, forPreferences: systemLanguages)
        return preferred.first ?? "en"
    }

    /// Reads the system-wide AppleLanguages, bypassing any per-app override.
    private static var globalPreferredLanguages: [String] {
        if let languages = CFPreferencesCopyValue(
            "AppleLanguages" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String] {
            return languages
        }
        return Locale.preferredLanguages
    }

    var locale: Locale {
        let selected = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system"
        if selected == "system" {
            return Locale(identifier: systemLanguageCode)
        }
        return Locale(identifier: selected)
    }
}

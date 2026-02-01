import Foundation

class LanguageManager {
    static let shared = LanguageManager()
    
    struct Language {
        let code: String
        let name: String
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
    
    var locale: Locale {
        let selected = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system"
        if selected == "system" {
            return Locale.current
        }
        return Locale(identifier: selected)
    }
}

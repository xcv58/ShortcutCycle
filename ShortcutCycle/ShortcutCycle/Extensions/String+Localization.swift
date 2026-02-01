import Foundation

extension String {
    func localized(language: String) -> String {
        let selectedLanguage = language == "system" ? Locale.current.language.languageCode?.identifier : language
        
        guard let code = selectedLanguage,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(self, comment: "")
        }
        
        return NSLocalizedString(self, tableName: nil, bundle: bundle, value: "", comment: "")
    }
}

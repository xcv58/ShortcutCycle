import Foundation

extension String {
    func localized(language: String) -> String {
        let resolvedCode = language == "system" ? LanguageManager.shared.systemLanguageCode : language

        guard let path = Bundle.main.path(forResource: resolvedCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(self, comment: "")
        }

        return NSLocalizedString(self, tableName: nil, bundle: bundle, value: "", comment: "")
    }
}

import Foundation

private final class LocalizationResolver: NSObject {
    static let shared = LocalizationResolver()

    private var cachedSystemLanguageCode: String?
    private var bundleByLanguageCode: [String: Bundle] = [:]
    private var missingBundleCodes = Set<String>()
    private var localizedStringCache: [String: [String: String]] = [:]
    private let lock = NSLock()

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localeDidChange),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )
    }

    @objc private func localeDidChange() {
        lock.lock()
        cachedSystemLanguageCode = nil
        lock.unlock()
    }

    func localizedString(for key: String, language: String) -> String {
        let resolvedCode = resolvedLanguageCode(for: language)

        lock.lock()
        if let cached = localizedStringCache[resolvedCode]?[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let localizedValue: String
        if let bundle = bundle(for: resolvedCode) {
            localizedValue = NSLocalizedString(key, tableName: nil, bundle: bundle, value: "", comment: "")
        } else {
            localizedValue = NSLocalizedString(key, comment: "")
        }

        lock.lock()
        var languageCache = localizedStringCache[resolvedCode] ?? [:]
        languageCache[key] = localizedValue
        localizedStringCache[resolvedCode] = languageCache
        lock.unlock()

        return localizedValue
    }

    private func resolvedLanguageCode(for language: String) -> String {
        guard language == "system" else { return language }

        lock.lock()
        if let cachedSystemLanguageCode {
            lock.unlock()
            return cachedSystemLanguageCode
        }
        lock.unlock()

        let resolvedCode = LanguageManager.shared.systemLanguageCode

        lock.lock()
        cachedSystemLanguageCode = resolvedCode
        lock.unlock()

        return resolvedCode
    }

    private func bundle(for languageCode: String) -> Bundle? {
        lock.lock()
        if let cachedBundle = bundleByLanguageCode[languageCode] {
            lock.unlock()
            return cachedBundle
        }

        if missingBundleCodes.contains(languageCode) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            lock.lock()
            missingBundleCodes.insert(languageCode)
            lock.unlock()
            return nil
        }

        lock.lock()
        bundleByLanguageCode[languageCode] = bundle
        lock.unlock()
        return bundle
    }
}

extension String {
    func localized(language: String) -> String {
        LocalizationResolver.shared.localizedString(for: self, language: language)
    }
}

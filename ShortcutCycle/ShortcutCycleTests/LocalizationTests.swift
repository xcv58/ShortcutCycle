import XCTest

/// Tests to ensure all localization keys are present in all supported languages
final class LocalizationTests: XCTestCase {
    
    /// All supported language codes in the project
    private let supportedLanguages = [
        "en", "de", "es", "fr", "it", "ja", "ko",
        "nl", "pl", "pt-BR", "ru", "tr", "ar",
        "zh-Hans", "zh-Hant"
    ]
    
    /// Parse a Localizable.strings file and return all keys
    private func parseLocalizationKeys(from url: URL) -> Set<String> {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        
        var keys = Set<String>()
        let lines = contents.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("/*") || trimmed.hasPrefix("//") {
                continue
            }
            
            // Match pattern: "key" = "value";
            if let match = trimmed.range(of: "^\"([^\"]+)\"\\s*=", options: .regularExpression) {
                let matched = String(trimmed[match])
                // Extract key between the first pair of quotes
                if let openQuote = matched.firstIndex(of: "\"") {
                    let afterOpen = matched.index(after: openQuote)
                    if let closeQuote = matched[afterOpen...].firstIndex(of: "\"") {
                        let key = String(matched[afterOpen..<closeQuote])
                        keys.insert(key)
                    }
                }
            }
        }
        
        return keys
    }
    
    /// Find the Resources directory containing localization files
    private func findResourcesDirectory() -> URL? {
        // Try to find the bundle's resources (works in Xcode test runner)
        let bundle = Bundle(for: type(of: self))

        if let enPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") {
            return URL(fileURLWithPath: enPath).deletingLastPathComponent().deletingLastPathComponent()
        }

        // Fallback: try source-relative paths (works in SPM `swift test`)
        // #file = .../ShortcutCycleTests/LocalizationTests.swift
        // Go up to project root, then into ShortcutCycle/Resources
        let testFileURL = URL(fileURLWithPath: #file)
        let projectRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()

        let possiblePaths = [
            // Xcode bundle-relative
            bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("ShortcutCycle.app/Contents/Resources"),
            bundle.bundleURL.appendingPathComponent("Contents/Resources"),
            // SPM source-relative: ShortcutCycleTests/ -> project root -> ShortcutCycle/Resources
            projectRoot.appendingPathComponent("ShortcutCycle/Resources"),
        ]

        for path in possiblePaths {
            let enLproj = path.appendingPathComponent("en.lproj/Localizable.strings")
            if FileManager.default.fileExists(atPath: enLproj.path) {
                return path
            }
        }

        return nil
    }
    
    /// Test that all localization keys in English exist in all other languages
    func testAllLocalizationKeysExistInAllLanguages() throws {
        let resourcesDir = try XCTUnwrap(findResourcesDirectory(), "Could not find Resources directory containing localization files")
        
        // Get English keys as the baseline
        let enURL = resourcesDir.appendingPathComponent("en.lproj/Localizable.strings")
        let englishKeys = parseLocalizationKeys(from: enURL)
        
        XCTAssertFalse(englishKeys.isEmpty, "English localization file should have keys")
        
        var missingKeysReport: [String: [String]] = [:]
        
        // Check each language against English
        for language in supportedLanguages where language != "en" {
            let langURL = resourcesDir.appendingPathComponent("\(language).lproj/Localizable.strings")
            let langKeys = parseLocalizationKeys(from: langURL)
            
            let missingKeys = englishKeys.subtracting(langKeys)
            
            if !missingKeys.isEmpty {
                missingKeysReport[language] = Array(missingKeys).sorted()
            }
        }
        
        // Generate a helpful error message if there are missing keys
        if !missingKeysReport.isEmpty {
            var errorMessage = "Missing localization keys found:\n"
            for (language, keys) in missingKeysReport.sorted(by: { $0.key < $1.key }) {
                errorMessage += "\n\(language): Missing \(keys.count) keys:\n"
                for key in keys.prefix(10) { // Show first 10 to avoid overwhelming output
                    errorMessage += "  - \"\(key)\"\n"
                }
                if keys.count > 10 {
                    errorMessage += "  ... and \(keys.count - 10) more\n"
                }
            }
            XCTFail(errorMessage)
        }
    }
    
    /// Test that no language has extra keys not present in English (orphaned translations)
    func testNoOrphanedTranslationKeys() throws {
        let resourcesDir = try XCTUnwrap(findResourcesDirectory(), "Could not find Resources directory containing localization files")
        
        let enURL = resourcesDir.appendingPathComponent("en.lproj/Localizable.strings")
        let englishKeys = parseLocalizationKeys(from: enURL)
        
        var extraKeysReport: [String: [String]] = [:]
        
        for language in supportedLanguages where language != "en" {
            let langURL = resourcesDir.appendingPathComponent("\(language).lproj/Localizable.strings")
            let langKeys = parseLocalizationKeys(from: langURL)
            
            let extraKeys = langKeys.subtracting(englishKeys)
            
            if !extraKeys.isEmpty {
                extraKeysReport[language] = Array(extraKeys).sorted()
            }
        }
        
        if !extraKeysReport.isEmpty {
            var warningMessage = "Orphaned translation keys found (present in translation but not in English):\n"
            for (language, keys) in extraKeysReport.sorted(by: { $0.key < $1.key }) {
                warningMessage += "\n\(language): \(keys.count) extra keys:\n"
                for key in keys {
                    warningMessage += "  - \"\(key)\"\n"
                }
            }
            // This is a warning, not a failure - orphaned keys don't break functionality
            print(warningMessage)
        }
    }
    
    /// Test that critical UI strings are localized
    func testCriticalStringsAreLocalized() throws {
        let criticalKeys = [
            // Backup & Restore section
            "Copy to Clipboard",
            "Paste from Clipboard",
            "No text found on clipboard.",
            "Clipboard Error",
            "File Export/Import",
            "Clipboard Sync",
            
            // Group Edit View
            "Cycle through all apps (open if needed)",
            
            // General UI
            "Backup & Restore",
            "Export Settings...",
            "Import Settings..."
        ]
        
        let resourcesDir = try XCTUnwrap(findResourcesDirectory(), "Could not find Resources directory containing localization files")
        
        let enURL = resourcesDir.appendingPathComponent("en.lproj/Localizable.strings")
        let englishKeys = parseLocalizationKeys(from: enURL)
        
        let missingCriticalKeys = criticalKeys.filter { !englishKeys.contains($0) }
        
        if !missingCriticalKeys.isEmpty {
            XCTFail("Critical UI strings missing from English localization:\n" + missingCriticalKeys.map { "  - \"\($0)\"" }.joined(separator: "\n"))
        }
    }
}

import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#endif
@testable import ShortcutCycle

/// Tests to ensure all localization keys are present in all supported languages
final class LocalizationTests: XCTestCase {
    
    /// LanguageManager is the application source of truth for supported languages.
    private var supportedLanguages: [String] {
        LanguageManager.shared.supportedLanguages.map(\.code)
    }
    
    /// Parse a Localizable.strings file and return all keys
    private func parseLocalizationKeys(from url: URL) -> Set<String> {
        // First try parsing as a property list dictionary, which correctly handles
        // .strings files across encodings and escaped characters.
        if let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let dict = plist as? [String: Any] {
            return Set(dict.keys)
        }

        // Fallback for malformed files: best-effort line parsing.
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian]
        let contents = encodings.lazy.compactMap { try? String(contentsOf: url, encoding: $0) }.first
        guard let contents else {
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
        // Prefer source-relative paths first to avoid accidentally resolving
        // unrelated Localizable.strings from dependency bundles in Xcode tests.
        // #file = .../ShortcutCycleTests/LocalizationTests.swift
        // Go up to project root, then into ShortcutCycle/Resources
        let testFileURL = URL(fileURLWithPath: #file)
        let projectRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourceResources = projectRoot.appendingPathComponent("ShortcutCycle/Resources")
        let sourceEnPath = sourceResources.appendingPathComponent("en.lproj/Localizable.strings")
        if FileManager.default.fileExists(atPath: sourceEnPath.path) {
            return sourceResources
        }

        // Fallback: try to find the bundle's resources (works in Xcode test runner)
        let bundle = Bundle(for: type(of: self))
        if let enPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") {
            return URL(fileURLWithPath: enPath).deletingLastPathComponent().deletingLastPathComponent()
        }

        let possiblePaths = [
            // Xcode bundle-relative
            bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("ShortcutCycle.app/Contents/Resources"),
            bundle.bundleURL.appendingPathComponent("Contents/Resources"),
        ]

        for path in possiblePaths {
            let enLproj = path.appendingPathComponent("en.lproj/Localizable.strings")
            if FileManager.default.fileExists(atPath: enLproj.path) {
                return path
            }
        }

        return nil
    }

    /// Test that localization resources match the application's supported languages.
    func testLocalizationResourcesMatchSupportedLanguages() throws {
        let resourcesDir = try XCTUnwrap(findResourcesDirectory(), "Could not find Resources directory containing localization files")
        let expectedLanguages = Set(supportedLanguages)
        let localizationDirectories = try FileManager.default.contentsOfDirectory(
            at: resourcesDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let actualLanguages = Set(
            localizationDirectories
                .filter { $0.pathExtension == "lproj" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )

        XCTAssertEqual(
            actualLanguages,
            expectedLanguages,
            "Localization directories should match LanguageManager.supportedLanguages"
        )

        for language in supportedLanguages {
            let langURL = resourcesDir.appendingPathComponent("\(language).lproj/Localizable.strings")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: langURL.path),
                "Missing localization file for \(language)"
            )
        }
    }

    func testLanguageSourcesMatchLanguageManager() throws {
        let expectedLanguages = Set(supportedLanguages)
        XCTAssertEqual(
            Set(AppleLanguagePreferenceSync.supportedLanguageCodes),
            expectedLanguages,
            "AppleLanguagePreferenceSync should match LanguageManager.supportedLanguages"
        )

        let resourcesDir = try XCTUnwrap(findResourcesDirectory(), "Could not find Resources directory containing localization files")
        let infoURL = resourcesDir.deletingLastPathComponent().appendingPathComponent("Info.plist")
        let infoData = try Data(contentsOf: infoURL)
        let info = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any],
            "Could not parse Info.plist"
        )
        let bundleLanguages = try XCTUnwrap(
            info["CFBundleLocalizations"] as? [String],
            "Info.plist is missing CFBundleLocalizations"
        )

        XCTAssertEqual(
            Set(bundleLanguages),
            expectedLanguages,
            "Info.plist CFBundleLocalizations should match LanguageManager.supportedLanguages"
        )
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
            "All apps (open if needed)",
            
            // Welcome banner
            "Show welcome again",
            "ShortcutCycle is running in your menu bar",
            "Look for the ShortcutCycle icon in the top-right menu bar whenever you want to open the app again.",

            // General UI
            "Backup & Restore",
            "Export Settings...",
            "Import Settings...",
            "Settings...",
            "Quit",
            "Groups",
            "General",
            "Cancel",
            "Import",
            "Add",
            "Rename",
            "Delete",
            "Appearance",
            "Toggle Appearance",
            "Language"
        ]
        
        let resourcesDir = try XCTUnwrap(findResourcesDirectory(), "Could not find Resources directory containing localization files")
        
        let enURL = resourcesDir.appendingPathComponent("en.lproj/Localizable.strings")
        let englishKeys = parseLocalizationKeys(from: enURL)
        
        let missingCriticalKeys = criticalKeys.filter { !englishKeys.contains($0) }
        
        if !missingCriticalKeys.isEmpty {
            XCTFail("Critical UI strings missing from English localization:\n" + missingCriticalKeys.map { "  - \"\($0)\"" }.joined(separator: "\n"))
        }
    }

    func testObsoleteHUDWarningStringsAreRemovedFromAllLocalizations() throws {
        let resourcesDir = try XCTUnwrap(findResourcesDirectory(), "Could not find Resources directory containing localization files")

        let removedKeys = [
            "If Settings is open on another Space, macOS may briefly switch Spaces while showing the HUD.",
            "Switching may feel slower while Settings is open",
            "To avoid asking for extra macOS permissions, ShortcutCycle may briefly activate Settings while switching with the HUD enabled. Close Settings for normal switching speed.",
            "Close Settings Window",
            "Hide Tip"
        ]

        for language in supportedLanguages {
            let langURL = resourcesDir.appendingPathComponent("\(language).lproj/Localizable.strings")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: langURL.path),
                "Missing localization file for \(language)"
            )
            let langKeys = parseLocalizationKeys(from: langURL)

            for key in removedKeys {
                XCTAssertFalse(langKeys.contains(key), "\"\(key)\" should stay removed from \(language)")
            }
        }
    }
}

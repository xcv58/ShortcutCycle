import XCTest
import KeyboardShortcuts
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

@MainActor
final class SettingsExportTests: XCTestCase {

    // MARK: - Round-trip

    func testEncodeDecodeRoundTrip() throws {
        let groups = [
            AppGroup(name: "Test Group", apps: []),
            AppGroup(name: "Another Group", apps: [])
        ]
        let settings = AppSettings(showHUD: false, showShortcutInHUD: true, selectedLanguage: "ja", appTheme: "dark")
        let shortcuts: [String: ShortcutData] = [
            groups[0].id.uuidString: ShortcutData(carbonKeyCode: 0, carbonModifiers: 256)
        ]
        let export = SettingsExport(groups: groups, settings: settings, shortcuts: shortcuts)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SettingsExport.self, from: data)

        XCTAssertEqual(decoded.version, 3)
        XCTAssertEqual(decoded.groups.count, 2)
        XCTAssertEqual(decoded.groups[0].name, "Test Group")
        XCTAssertEqual(decoded.settings?.showHUD, false)
        XCTAssertEqual(decoded.settings?.appTheme, "dark")
        XCTAssertEqual(decoded.shortcuts?[groups[0].id.uuidString]?.carbonKeyCode, 0)
        XCTAssertEqual(decoded.shortcuts?[groups[0].id.uuidString]?.carbonModifiers, 256)
    }

    // MARK: - Unsupported legacy versions

    func testValidateVersion1IsInvalid() {
        let json = """
        {
            "version": 1,
            "exportDate": "2024-06-01T00:00:00Z",
            "groups": [
                {
                    "id": "\(UUID().uuidString)",
                    "name": "Old Group",
                    "apps": [],
                    "isEnabled": true,
                    "lastModified": "2024-01-01T00:00:00Z"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let result = SettingsExport.validate(data: data)

        guard case .failure(.invalidVersion) = result else {
            return XCTFail("Version 1 imports should be rejected")
        }
    }

    func testValidateVersion2IsInvalid() {
        let json = """
        {
            "version": 2,
            "exportDate": "2025-01-01T00:00:00Z",
            "groups": [],
            "settings": {
                "showHUD": true,
                "showShortcutInHUD": false,
                "selectedLanguage": "en"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let result = SettingsExport.validate(data: data)

        guard case .failure(.invalidVersion) = result else {
            return XCTFail("Version 2 imports should be rejected")
        }
    }

    // MARK: - ShortcutData round-trip

    func testShortcutDataRoundTrip() throws {
        let original = ShortcutData(carbonKeyCode: 42, carbonModifiers: 768)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShortcutData.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testShortcutDataEquatable() {
        let a = ShortcutData(carbonKeyCode: 42, carbonModifiers: 768)
        let b = ShortcutData(carbonKeyCode: 42, carbonModifiers: 768)
        let c = ShortcutData(carbonKeyCode: 43, carbonModifiers: 768)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testShortcutDataConvertsToAndFromKeyboardShortcut() {
        let shortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.option])
        let data = ShortcutData(shortcut)

        XCTAssertEqual(data.shortcut, shortcut)
    }

    // MARK: - AppSettings

    func testAppSettingsIncludesAppTheme() throws {
        let settings = AppSettings(showHUD: true, showShortcutInHUD: true, selectedLanguage: "en", appTheme: "light")
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.appTheme, "light")
    }

    func testAppSettingsWithAllNilOptionals() throws {
        let settings = AppSettings(showHUD: false, showShortcutInHUD: false)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertFalse(decoded.showHUD)
        XCTAssertFalse(decoded.showShortcutInHUD)
        XCTAssertNil(decoded.selectedLanguage)
        XCTAssertNil(decoded.appTheme)
    }

    func testAppSettingsEquatable() {
        let a = AppSettings(showHUD: true, showShortcutInHUD: true, selectedLanguage: "en", appTheme: "dark")
        let b = AppSettings(showHUD: true, showShortcutInHUD: true, selectedLanguage: "en", appTheme: "dark")
        let c = AppSettings(showHUD: false, showShortcutInHUD: true, selectedLanguage: "en", appTheme: "dark")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testAppSettingsRoundTrip() throws {
        let original = AppSettings(showHUD: false, showShortcutInHUD: true, selectedLanguage: "ja", appTheme: "light")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.showHUD, false)
        XCTAssertEqual(decoded.showShortcutInHUD, true)
        XCTAssertEqual(decoded.selectedLanguage, "ja")
        XCTAssertEqual(decoded.appTheme, "light")
    }

    // MARK: - Validation tests

    func testValidateValidJSON() {
        let json = """
        {
            "version": 3,
            "exportDate": "2025-01-01T00:00:00Z",
            "groups": [],
            "settings": {
                "showHUD": true,
                "showShortcutInHUD": true,
                "selectedLanguage": "system",
                "appTheme": "system"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let result = SettingsExport.validate(data: data)
        switch result {
        case .success(let export):
            XCTAssertEqual(export.version, 3)
        case .failure(let error):
            XCTFail("Validation should succeed: \(error)")
        }
    }

    func testValidateEmptyString() {
        let data = "".data(using: .utf8)!
        let result = SettingsExport.validate(data: data)
        switch result {
        case .success:
            XCTFail("Should fail for empty string")
        case .failure:
            break // expected
        }
    }

    func testValidateRandomText() {
        let data = "this is not json at all".data(using: .utf8)!
        let result = SettingsExport.validate(data: data)
        switch result {
        case .success:
            XCTFail("Should fail for random text")
        case .failure:
            break // expected
        }
    }

    func testValidateWrongSchema() {
        let json = """
        {"foo": 1}
        """
        let data = json.data(using: .utf8)!
        let result = SettingsExport.validate(data: data)
        switch result {
        case .success:
            XCTFail("Should fail for wrong schema")
        case .failure:
            break // expected
        }
    }

    func testValidateFutureVersionIsInvalid() {
        let json = """
        {
            "version": 999,
            "exportDate": "2025-01-01T00:00:00Z",
            "groups": []
        }
        """
        let data = json.data(using: .utf8)!
        let result = SettingsExport.validate(data: data)
        switch result {
        case .success:
            XCTFail("Future versions should not be imported destructively")
        case .failure(let error):
            guard case .invalidVersion = error else {
                XCTFail("Expected invalidVersion error, got: \(error)")
                return
            }
        }
    }

    func testValidateVersionZeroIsInvalid() {
        let json = """
        {
            "version": 0,
            "exportDate": "2025-01-01T00:00:00Z",
            "groups": []
        }
        """
        let data = json.data(using: .utf8)!
        let result = SettingsExport.validate(data: data)
        switch result {
        case .success:
            XCTFail("Version 0 should be invalid")
        case .failure(let error):
            guard case .invalidVersion = error else {
                XCTFail("Expected invalidVersion error, got: \(error)")
                return
            }
        }
    }

    func testValidateNegativeVersionIsInvalid() {
        let json = """
        {
            "version": -1,
            "exportDate": "2025-01-01T00:00:00Z",
            "groups": []
        }
        """
        let data = json.data(using: .utf8)!
        let result = SettingsExport.validate(data: data)
        switch result {
        case .success:
            XCTFail("Negative version should be invalid")
        case .failure:
            break // expected
        }
    }

    // MARK: - SettingsExportError

    func testErrorDescriptions() {
        let formatError = SettingsExportError.invalidFormat("bad json")
        XCTAssertTrue(formatError.errorDescription?.contains("bad json") ?? false)

        let versionError = SettingsExportError.invalidVersion
        XCTAssertNotNil(versionError.errorDescription)

        let emptyError = SettingsExportError.emptyData
        XCTAssertNotNil(emptyError.errorDescription)
    }

    // MARK: - SettingsExport initialization

    func testCurrentVersionIs3() {
        XCTAssertEqual(SettingsExport.currentVersion, 3)
    }

    func testInitSetsVersionAndDate() {
        let export = SettingsExport(groups: [])

        XCTAssertEqual(export.version, 3)
        XCTAssertNotNil(export.exportDate)
        // Date should be recent (within last minute)
        XCTAssertLessThan(abs(export.exportDate.timeIntervalSinceNow), 60)
    }

    func testInitWithNilSettingsAndShortcuts() {
        let export = SettingsExport(groups: [AppGroup(name: "G")])

        XCTAssertNil(export.settings)
        XCTAssertNil(export.shortcuts)
        XCTAssertEqual(export.groups.count, 1)
    }

    // MARK: - Round-trip with groups containing apps

    func testRoundTripWithApps() throws {
        let app1 = AppItem(bundleIdentifier: "com.test.1", name: "App 1", iconPath: "/path/1")
        let app2 = AppItem(bundleIdentifier: "com.test.2", name: "App 2")
        let group = AppGroup(name: "With Apps", apps: [app1, app2])
        let export = SettingsExport(groups: [group])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SettingsExport.self, from: data)

        XCTAssertEqual(decoded.groups[0].apps.count, 2)
        XCTAssertEqual(decoded.groups[0].apps[0].bundleIdentifier, "com.test.1")
        XCTAssertEqual(decoded.groups[0].apps[0].iconPath, "/path/1")
        XCTAssertEqual(decoded.groups[0].apps[1].bundleIdentifier, "com.test.2")
        XCTAssertNil(decoded.groups[0].apps[1].iconPath)
    }

    func testRoundTripWithMultipleShortcuts() throws {
        let group1 = AppGroup(name: "G1")
        let group2 = AppGroup(name: "G2")
        let shortcuts: [String: ShortcutData] = [
            group1.id.uuidString: ShortcutData(carbonKeyCode: 0, carbonModifiers: 256),
            group2.id.uuidString: ShortcutData(carbonKeyCode: 1, carbonModifiers: 512)
        ]
        let export = SettingsExport(groups: [group1, group2], shortcuts: shortcuts)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SettingsExport.self, from: data)

        XCTAssertEqual(decoded.shortcuts?.count, 2)
        XCTAssertEqual(decoded.shortcuts?[group1.id.uuidString]?.carbonKeyCode, 0)
        XCTAssertEqual(decoded.shortcuts?[group2.id.uuidString]?.carbonKeyCode, 1)
    }

    // MARK: - Auto-backup

    func testAutoBackupCreatesFile() throws {
        let userDefaults = UserDefaults(suiteName: "TestAutoBackup")!
        userDefaults.removePersistentDomain(forName: "TestAutoBackup")
        let store = GroupStore(userDefaults: userDefaults)

        // Trigger a save by adding a group
        _ = store.addGroup(name: "Backup Test")

        // Flush the debounced backup immediately (normally waits 60 seconds)
        store.flushPendingBackup()

        // Check backup file exists in test directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let backupDir = appSupport.appendingPathComponent("ShortcutCycle-Test", isDirectory: true)

        // Find the most recent backup file (has timestamp in name)
        let files = try fileManager.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)
        let backupFiles = files.filter { $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json" }

        XCTAssertFalse(backupFiles.isEmpty, "No backup files found")

        // Verify the most recent one is valid JSON
        let latestBackup = backupFiles.sorted { $0.lastPathComponent > $1.lastPathComponent }.first!
        let data = try Data(contentsOf: latestBackup)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(SettingsExport.self, from: data)
        XCTAssertGreaterThan(export.groups.count, 0)

        // Cleanup
        userDefaults.removePersistentDomain(forName: "TestAutoBackup")
        try? FileManager.default.removeItem(at: backupDir)
    }

    // MARK: - AppSettings.current() and apply()

    func testAppSettingsCurrentReadsFromUserDefaults() {
        // Save known values to UserDefaults.standard
        let defaults = UserDefaults.standard
        let originalShowHUD = defaults.object(forKey: "showHUD")
        let originalShowShortcut = defaults.object(forKey: "showShortcutInHUD")
        let originalLanguage = defaults.string(forKey: "selectedLanguage")
        let originalTheme = defaults.string(forKey: "appTheme")
        defer {
            // Restore original values
            if let v = originalShowHUD { defaults.set(v, forKey: "showHUD") } else { defaults.removeObject(forKey: "showHUD") }
            if let v = originalShowShortcut { defaults.set(v, forKey: "showShortcutInHUD") } else { defaults.removeObject(forKey: "showShortcutInHUD") }
            if let v = originalLanguage { defaults.set(v, forKey: "selectedLanguage") } else { defaults.removeObject(forKey: "selectedLanguage") }
            if let v = originalTheme { defaults.set(v, forKey: "appTheme") } else { defaults.removeObject(forKey: "appTheme") }
        }

        defaults.set(false, forKey: "showHUD")
        defaults.set(false, forKey: "showShortcutInHUD")
        defaults.set("fr", forKey: "selectedLanguage")
        defaults.set("dark", forKey: "appTheme")

        let current = AppSettings.current()
        XCTAssertEqual(current.showHUD, false)
        XCTAssertEqual(current.showShortcutInHUD, false)
        XCTAssertEqual(current.selectedLanguage, "fr")
        XCTAssertEqual(current.appTheme, "dark")
    }

    func testAppSettingsCurrentDefaultValues() {
        let suiteName = "SettingsExportTests.Defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("invalid", forKey: "showHUD")
        defaults.set("invalid", forKey: "showShortcutInHUD")

        let current = AppSettings.current(userDefaults: defaults)
        XCTAssertEqual(current.showHUD, true)
        XCTAssertEqual(current.showShortcutInHUD, true)
        XCTAssertEqual(current.selectedLanguage, "system")
        XCTAssertEqual(current.appTheme, "system")
    }

    func testAppSettingsApply() {
        let defaults = UserDefaults.standard
        let originalShowHUD = defaults.object(forKey: "showHUD")
        let originalShowShortcut = defaults.object(forKey: "showShortcutInHUD")
        let originalLanguage = defaults.string(forKey: "selectedLanguage")
        let originalAppleLanguages = defaults.stringArray(forKey: "AppleLanguages")
        let originalTheme = defaults.string(forKey: "appTheme")
        defer {
            if let v = originalShowHUD { defaults.set(v, forKey: "showHUD") } else { defaults.removeObject(forKey: "showHUD") }
            if let v = originalShowShortcut { defaults.set(v, forKey: "showShortcutInHUD") } else { defaults.removeObject(forKey: "showShortcutInHUD") }
            if let v = originalLanguage { defaults.set(v, forKey: "selectedLanguage") } else { defaults.removeObject(forKey: "selectedLanguage") }
            if let v = originalAppleLanguages { defaults.set(v, forKey: "AppleLanguages") } else { defaults.removeObject(forKey: "AppleLanguages") }
            if let v = originalTheme { defaults.set(v, forKey: "appTheme") } else { defaults.removeObject(forKey: "appTheme") }
        }

        let settings = AppSettings(showHUD: false, showShortcutInHUD: true, selectedLanguage: "ko", appTheme: "light")
        settings.apply()

        XCTAssertEqual(defaults.bool(forKey: "showHUD"), false)
        XCTAssertEqual(defaults.bool(forKey: "showShortcutInHUD"), true)
        XCTAssertEqual(defaults.string(forKey: "selectedLanguage"), "ko")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["ko"])
        XCTAssertEqual(defaults.string(forKey: "appTheme"), "light")
    }

    func testAppleLanguagePreferenceSyncFallsBackToLocalePreferredLanguages() {
        XCTAssertEqual(
            AppleLanguagePreferenceSync.resolvedPreferredLanguages(
                from: nil,
                fallback: ["ja"]
            ),
            ["ja"]
        )
    }

    func testAppleLanguagePreferenceSyncResolvesSystemAndExplicitLanguages() {
        XCTAssertEqual(
            AppleLanguagePreferenceSync.effectiveLanguageCode(
                selectedLanguage: "system",
                preferredLocalization: "ja"
            ),
            "ja"
        )
        XCTAssertEqual(
            AppleLanguagePreferenceSync.effectiveLanguageCode(
                selectedLanguage: "system",
                preferredLocalization: nil
            ),
            "en"
        )
        XCTAssertEqual(
            AppleLanguagePreferenceSync.effectiveLanguageCode(
                selectedLanguage: "de",
                preferredLocalization: "ja"
            ),
            "de"
        )
        XCTAssertEqual(AppleLanguagePreferenceSync.appleLanguageCode(for: "zh-Hant"), "zh-TW")
        XCTAssertEqual(AppleLanguagePreferenceSync.appleLanguageCode(for: "fr"), "fr")
    }

    func testAppSettingsApplyWithNilThemeDoesNotWrite() {
        let defaults = UserDefaults.standard
        let originalTheme = defaults.string(forKey: "appTheme")
        defer {
            if let v = originalTheme { defaults.set(v, forKey: "appTheme") } else { defaults.removeObject(forKey: "appTheme") }
        }

        defaults.set("existing", forKey: "appTheme")

        let settings = AppSettings(showHUD: true, showShortcutInHUD: true, selectedLanguage: nil, appTheme: nil)
        settings.apply()

        // nil appTheme should NOT overwrite existing value
        XCTAssertEqual(defaults.string(forKey: "appTheme"), "existing")
        // nil selectedLanguage should write "system"
        XCTAssertEqual(defaults.string(forKey: "selectedLanguage"), "system")
    }

    // MARK: - fullSnapshot

    func testFullSnapshotCapturesGroups() {
        let groups = [AppGroup(name: "Snap"), AppGroup(name: "Shot")]
        let snapshot = SettingsExport.fullSnapshot(groups: groups)

        XCTAssertEqual(snapshot.groups.count, 2)
        XCTAssertEqual(snapshot.groups[0].name, "Snap")
        XCTAssertEqual(snapshot.groups[1].name, "Shot")
        XCTAssertEqual(snapshot.version, 3)
        XCTAssertNotNil(snapshot.settings)
    }

    func testFullSnapshotCapturesRegisteredShortcuts() {
        let group = AppGroup(name: "WithShortcut")
        let shortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: 42, carbonModifiers: 768)
        KeyboardShortcuts.setShortcut(shortcut, for: group.shortcutName)
        defer { KeyboardShortcuts.setShortcut(nil, for: group.shortcutName) }

        let snapshot = SettingsExport.fullSnapshot(groups: [group])

        XCTAssertNotNil(snapshot.shortcuts)
        let data = snapshot.shortcuts?[group.id.uuidString]
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.carbonKeyCode, 42)
        XCTAssertEqual(data?.carbonModifiers, 768)
    }

    func testFullSnapshotWithNoShortcutsRegistered() {
        let groups = [AppGroup(name: "NoShortcut")]
        let snapshot = SettingsExport.fullSnapshot(groups: groups)

        // In test environment, no shortcuts are registered
        XCTAssertNil(snapshot.shortcuts)
    }

    func testFullSnapshotWithEmptyGroups() {
        let snapshot = SettingsExport.fullSnapshot(groups: [])

        XCTAssertTrue(snapshot.groups.isEmpty)
        XCTAssertNil(snapshot.shortcuts)
    }

    // MARK: - applyShortcuts

    func testApplyShortcutsWithNilShortcuts() {
        let group = AppGroup(name: "G")
        let existingShortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [.command])
        KeyboardShortcuts.setShortcut(existingShortcut, for: group.shortcutName)
        let export = SettingsExport(groups: [group])
        defer { KeyboardShortcuts.setShortcut(nil, for: group.shortcutName) }

        XCTAssertNil(export.applyShortcuts { _, _ in nil })
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: group.shortcutName))
    }

    func testApplyShortcutsWithShortcutData() {
        let group = AppGroup(name: "WithShortcut")
        let shortcuts: [String: ShortcutData] = [
            group.id.uuidString: ShortcutData(carbonKeyCode: 0, carbonModifiers: 256)
        ]
        let export = SettingsExport(groups: [group], shortcuts: shortcuts)
        defer { KeyboardShortcuts.setShortcut(nil, for: group.shortcutName) }

        XCTAssertNil(export.applyShortcuts { _, _ in nil })
        XCTAssertEqual(
            KeyboardShortcuts.getShortcut(for: group.shortcutName),
            shortcuts[group.id.uuidString]?.shortcut
        )
    }

    func testApplyShortcutsIgnoresUnmatchedKeys() {
        let group = AppGroup(name: "G")
        let shortcuts: [String: ShortcutData] = [
            UUID().uuidString: ShortcutData(carbonKeyCode: 42, carbonModifiers: 512)
        ]
        let export = SettingsExport(groups: [group], shortcuts: shortcuts)
        KeyboardShortcuts.setShortcut(.init(.b, modifiers: [.command]), for: group.shortcutName)
        defer { KeyboardShortcuts.setShortcut(nil, for: group.shortcutName) }

        XCTAssertNil(export.applyShortcuts { _, _ in nil })
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: group.shortcutName))
    }

    func testApplyShortcutsClearsRemovedGroupAssignment() {
        let removedGroup = AppGroup(name: "Removed")
        let importedGroup = AppGroup(name: "Imported")
        KeyboardShortcuts.setShortcut(
            .init(.a, modifiers: [.command]),
            for: removedGroup.shortcutName
        )
        let export = SettingsExport(groups: [importedGroup])
        defer { KeyboardShortcuts.setShortcut(nil, for: removedGroup.shortcutName) }

        XCTAssertNil(export.applyShortcuts { _, _ in nil })
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: removedGroup.shortcutName))
    }

    func testApplyShortcutsPreservesSettingsWindowAssignment() {
        let group = AppGroup(name: "Imported")
        let settingsShortcut = KeyboardShortcuts.Shortcut(.f20)
        let groupShortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.option])
        KeyboardShortcuts.setShortcut(settingsShortcut, for: .toggleSettings)
        let export = SettingsExport(
            groups: [group],
            shortcuts: [group.id.uuidString: ShortcutData(groupShortcut)]
        )
        defer {
            KeyboardShortcuts.setShortcut(nil, for: .toggleSettings)
            KeyboardShortcuts.setShortcut(nil, for: group.shortcutName)
        }

        XCTAssertNil(export.applyShortcuts { _, _ in nil })
        XCTAssertEqual(
            KeyboardShortcuts.getShortcut(for: .toggleSettings),
            settingsShortcut
        )
        XCTAssertEqual(
            KeyboardShortcuts.getShortcut(for: group.shortcutName),
            groupShortcut
        )
    }

    func testApplyShortcutsRejectsBeforeApplyingAnyShortcut() {
        let firstGroup = AppGroup(name: "First")
        let secondGroup = AppGroup(name: "Second")
        let firstShortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [.command])
        let secondShortcut = KeyboardShortcuts.Shortcut(.b, modifiers: [.command])
        let export = SettingsExport(
            groups: [firstGroup, secondGroup],
            shortcuts: [
                firstGroup.id.uuidString: ShortcutData(firstShortcut),
                secondGroup.id.uuidString: ShortcutData(secondShortcut)
            ]
        )
        defer {
            KeyboardShortcuts.setShortcut(nil, for: firstGroup.shortcutName)
            KeyboardShortcuts.setShortcut(nil, for: secondGroup.shortcutName)
        }

        let rejection = export.applyShortcuts { shortcut, _ in
            guard shortcut == secondShortcut else { return nil }
            return .conflict(
                ShortcutAssignmentConflict(
                    shortcut: shortcut,
                    owner: .appCommand(titleKey: "Reserved")
                )
            )
        }

        XCTAssertEqual(
            rejection,
            .conflict(
                ShortcutAssignmentConflict(
                    shortcut: secondShortcut,
                    owner: .appCommand(titleKey: "Reserved")
                )
            )
        )
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: firstGroup.shortcutName))
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: secondGroup.shortcutName))
    }

    func testApplyShortcutsRejectsDuplicateImportedAssignments() {
        let firstGroup = AppGroup(name: "First")
        let secondGroup = AppGroup(name: "Second")
        let shortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [.command])
        let export = SettingsExport(
            groups: [firstGroup, secondGroup],
            shortcuts: [
                firstGroup.id.uuidString: ShortcutData(shortcut),
                secondGroup.id.uuidString: ShortcutData(shortcut)
            ]
        )
        defer {
            KeyboardShortcuts.setShortcut(nil, for: firstGroup.shortcutName)
            KeyboardShortcuts.setShortcut(nil, for: secondGroup.shortcutName)
        }

        let rejection = export.applyShortcuts { _, _ in nil }

        XCTAssertEqual(
            rejection,
            .conflict(
                ShortcutAssignmentConflict(
                    shortcut: shortcut,
                    owner: .group(id: firstGroup.id, name: firstGroup.name)
                )
            )
        )
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: firstGroup.shortcutName))
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: secondGroup.shortcutName))
    }

    func testApplyShortcutsRejectsIneligibleAssignmentForms() {
        let group = AppGroup(name: "Imported")
        let ineligibleShortcuts: [(KeyboardShortcuts.Shortcut, ShortcutAssignmentRejection)] = [
            (.init(.a), .requiresModifier),
            (.init(.a, modifiers: [.shift]), .requiresModifier),
            (.init(.a, modifiers: [.function]), .requiresModifier),
            (.init(.a, modifiers: [.shift, .function]), .requiresModifier),
            (.init(.command, modifiers: [.command]), .invalidShortcut)
        ]
        defer { KeyboardShortcuts.setShortcut(nil, for: group.shortcutName) }

        for (shortcut, expectedRejection) in ineligibleShortcuts {
            let export = SettingsExport(
                groups: [group],
                shortcuts: [group.id.uuidString: ShortcutData(shortcut)]
            )

            XCTAssertEqual(
                export.applyShortcuts { _, _ in nil },
                expectedRejection
            )
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: group.shortcutName))
        }
    }

    func testApplyShortcutsAllowsEveryModifierlessFunctionKey() {
        let group = AppGroup(name: "Imported")
        let functionKeys: [KeyboardShortcuts.Key] = [
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20
        ]
        defer { KeyboardShortcuts.setShortcut(nil, for: group.shortcutName) }

        for key in functionKeys {
            let shortcut = KeyboardShortcuts.Shortcut(key)
            let export = SettingsExport(
                groups: [group],
                shortcuts: [group.id.uuidString: ShortcutData(shortcut)]
            )

            XCTAssertNil(export.applyShortcuts { _, _ in nil })
            XCTAssertEqual(
                KeyboardShortcuts.getShortcut(for: group.shortcutName),
                shortcut
            )
        }
    }

    func testApplyShortcutsRejectsMalformedRawValuesAtomically() {
        let existingGroup = AppGroup(name: "Existing")
        let importedGroup = AppGroup(name: "Imported")
        let existingShortcut = KeyboardShortcuts.Shortcut(.f20)
        KeyboardShortcuts.setShortcut(existingShortcut, for: existingGroup.shortcutName)
        defer {
            KeyboardShortcuts.setShortcut(nil, for: existingGroup.shortcutName)
            KeyboardShortcuts.setShortcut(nil, for: importedGroup.shortcutName)
        }

        let malformedValues: [ShortcutData] = [
            ShortcutData(carbonKeyCode: -1, carbonModifiers: 0),
            ShortcutData(carbonKeyCode: Int.max, carbonModifiers: 0),
            ShortcutData(
                carbonKeyCode: 0x7F,
                carbonModifiers: KeyboardShortcuts.Shortcut(
                    .a,
                    modifiers: [.command]
                ).carbonModifiers
            ),
            ShortcutData(
                carbonKeyCode: KeyboardShortcuts.Key.a.rawValue,
                carbonModifiers: Int.max
            )
        ]

        for malformed in malformedValues {
            let export = SettingsExport(
                groups: [importedGroup],
                shortcuts: [importedGroup.id.uuidString: malformed]
            )

            XCTAssertEqual(
                export.applyShortcuts { _, _ in nil },
                .invalidShortcut
            )
            XCTAssertEqual(
                KeyboardShortcuts.getShortcut(for: existingGroup.shortcutName),
                existingShortcut
            )
            XCTAssertNil(KeyboardShortcuts.getShortcut(for: importedGroup.shortcutName))
        }
    }

    func testApplyShortcutsRejectsMalformedRecentHistoryAtomically() {
        let existingGroup = AppGroup(name: "Existing")
        let existingShortcut = KeyboardShortcuts.Shortcut(.f20)
        KeyboardShortcuts.setShortcut(existingShortcut, for: existingGroup.shortcutName)
        defer { KeyboardShortcuts.setShortcut(nil, for: existingGroup.shortcutName) }

        let malformedValues: [ShortcutData] = [
            ShortcutData(carbonKeyCode: -1, carbonModifiers: 0),
            ShortcutData(carbonKeyCode: Int.max, carbonModifiers: 0),
            ShortcutData(carbonKeyCode: 0x7F, carbonModifiers: 0),
            ShortcutData(
                carbonKeyCode: KeyboardShortcuts.Key.a.rawValue,
                carbonModifiers: Int.max
            )
        ]

        for malformed in malformedValues {
            let importedGroup = AppGroup(
                name: "Imported",
                recentShortcuts: [malformed]
            )
            let export = SettingsExport(groups: [importedGroup])

            XCTAssertEqual(
                export.applyShortcuts { _, _ in nil },
                .invalidShortcut
            )
            XCTAssertEqual(
                KeyboardShortcuts.getShortcut(for: existingGroup.shortcutName),
                existingShortcut
            )
        }
    }

    func testApplyShortcutsAllowsRawValidIneligibleRecentHistory() {
        let recentShortcut = KeyboardShortcuts.Shortcut(.a)
        let group = AppGroup(
            name: "Imported",
            recentShortcuts: [ShortcutData(recentShortcut)]
        )
        let export = SettingsExport(groups: [group])

        XCTAssertNil(export.applyShortcuts { _, _ in nil })
        XCTAssertEqual(group.recentShortcuts, [ShortcutData(recentShortcut)])
    }

}

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

    // MARK: - Version backward compatibility

    func testVersion1BackwardCompatibility() throws {
        // v1 JSON has only version, exportDate, and groups (no settings or shortcuts)
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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SettingsExport.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.groups.count, 1)
        XCTAssertEqual(decoded.groups[0].name, "Old Group")
        XCTAssertNil(decoded.settings)
        XCTAssertNil(decoded.shortcuts)
    }

    func testVersion2BackwardCompatibility() throws {
        // v2 JSON has no shortcuts or appTheme fields
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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SettingsExport.self, from: data)

        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.groups.count, 0)
        XCTAssertEqual(decoded.settings?.showHUD, true)
        XCTAssertEqual(decoded.settings?.showShortcutInHUD, false)
        XCTAssertNil(decoded.shortcuts)
        XCTAssertNil(decoded.settings?.appTheme)
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

    func testValidateHighVersionStillValid() {
        // Future versions should still validate as long as structure is valid
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
        case .success(let export):
            XCTAssertEqual(export.version, 999)
        case .failure(let error):
            XCTFail("Future version should still validate: \(error)")
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
        // When keys are not set, defaults should apply
        let defaults = UserDefaults.standard
        let originalShowHUD = defaults.object(forKey: "showHUD")
        let originalShowShortcut = defaults.object(forKey: "showShortcutInHUD")
        let originalLanguage = defaults.string(forKey: "selectedLanguage")
        let originalTheme = defaults.string(forKey: "appTheme")
        defer {
            if let v = originalShowHUD { defaults.set(v, forKey: "showHUD") } else { defaults.removeObject(forKey: "showHUD") }
            if let v = originalShowShortcut { defaults.set(v, forKey: "showShortcutInHUD") } else { defaults.removeObject(forKey: "showShortcutInHUD") }
            if let v = originalLanguage { defaults.set(v, forKey: "selectedLanguage") } else { defaults.removeObject(forKey: "selectedLanguage") }
            if let v = originalTheme { defaults.set(v, forKey: "appTheme") } else { defaults.removeObject(forKey: "appTheme") }
        }

        defaults.removeObject(forKey: "showHUD")
        defaults.removeObject(forKey: "showShortcutInHUD")
        defaults.removeObject(forKey: "selectedLanguage")
        defaults.removeObject(forKey: "appTheme")

        let current = AppSettings.current()
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
        let originalTheme = defaults.string(forKey: "appTheme")
        defer {
            if let v = originalShowHUD { defaults.set(v, forKey: "showHUD") } else { defaults.removeObject(forKey: "showHUD") }
            if let v = originalShowShortcut { defaults.set(v, forKey: "showShortcutInHUD") } else { defaults.removeObject(forKey: "showShortcutInHUD") }
            if let v = originalLanguage { defaults.set(v, forKey: "selectedLanguage") } else { defaults.removeObject(forKey: "selectedLanguage") }
            if let v = originalTheme { defaults.set(v, forKey: "appTheme") } else { defaults.removeObject(forKey: "appTheme") }
        }

        let settings = AppSettings(showHUD: false, showShortcutInHUD: true, selectedLanguage: "ko", appTheme: "light")
        settings.apply()

        XCTAssertEqual(defaults.bool(forKey: "showHUD"), false)
        XCTAssertEqual(defaults.bool(forKey: "showShortcutInHUD"), true)
        XCTAssertEqual(defaults.string(forKey: "selectedLanguage"), "ko")
        XCTAssertEqual(defaults.string(forKey: "appTheme"), "light")
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
        let export = SettingsExport(groups: [AppGroup(name: "G")])

        // Should not crash when shortcuts is nil (early return)
        export.applyShortcuts()
    }

    func testApplyShortcutsWithShortcutData() {
        let group = AppGroup(name: "WithShortcut")
        let shortcuts: [String: ShortcutData] = [
            group.id.uuidString: ShortcutData(carbonKeyCode: 0, carbonModifiers: 256)
        ]
        let export = SettingsExport(groups: [group], shortcuts: shortcuts)

        // Should apply without crashing
        export.applyShortcuts()
    }

    func testApplyShortcutsIgnoresUnmatchedKeys() {
        let group = AppGroup(name: "G")
        let shortcuts: [String: ShortcutData] = [
            UUID().uuidString: ShortcutData(carbonKeyCode: 42, carbonModifiers: 512)
        ]
        let export = SettingsExport(groups: [group], shortcuts: shortcuts)

        // Shortcut key doesn't match any group — should not crash
        export.applyShortcuts()
    }

}

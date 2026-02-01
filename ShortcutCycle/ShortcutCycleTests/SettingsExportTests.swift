import XCTest
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

    // MARK: - Version 2 backward compatibility

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

    // MARK: - AppSettings includes appTheme

    func testAppSettingsIncludesAppTheme() throws {
        let settings = AppSettings(showHUD: true, showShortcutInHUD: true, selectedLanguage: "en", appTheme: "light")
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
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
    }
}

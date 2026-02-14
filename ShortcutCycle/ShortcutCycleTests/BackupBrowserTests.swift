import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

@MainActor
final class BackupBrowserTests: XCTestCase {

    // MARK: - Invalid Backup File

    func testInvalidBackupFileHandling() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let invalidFile = tempDir.appendingPathComponent("backup 2025-01-01 00-00-00.json")
        try Data("not valid json".utf8).write(to: invalidFile)

        let data = try Data(contentsOf: invalidFile)
        switch SettingsExport.validate(data: data) {
        case .success:
            XCTFail("Expected validation to fail for invalid JSON")
        case .failure:
            break // Expected
        }
    }

    // MARK: - Valid Backup File

    func testValidBackupFileRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let group = AppGroup(name: "Test", apps: [
            AppItem(bundleIdentifier: "com.test.app", name: "Test App")
        ])
        let export = SettingsExport(groups: [group])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)

        let backupFile = tempDir.appendingPathComponent("backup 2025-06-15 12-00-00.json")
        try data.write(to: backupFile)

        let readData = try Data(contentsOf: backupFile)
        let result = SettingsExport.validate(data: readData)
        switch result {
        case .success(let decoded):
            XCTAssertEqual(decoded.groups.count, 1)
            XCTAssertEqual(decoded.groups[0].name, "Test")
            XCTAssertEqual(decoded.groups[0].apps.count, 1)
        case .failure(let error):
            XCTFail("Expected validation to succeed: \(error)")
        }
    }

    // MARK: - Backup Directory Listing

    func testBackupDirectoryWithMixedFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create some backup files and some non-backup files
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let export = SettingsExport(groups: [AppGroup(name: "G")])
        let data = try encoder.encode(export)

        try data.write(to: tempDir.appendingPathComponent("backup 2025-01-01 00-00-00.json"))
        try data.write(to: tempDir.appendingPathComponent("backup 2025-01-02 00-00-00.json"))
        try Data("random".utf8).write(to: tempDir.appendingPathComponent("not-a-backup.json"))
        try Data("other".utf8).write(to: tempDir.appendingPathComponent("backup.txt"))

        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let backupFiles = files.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        }

        XCTAssertEqual(backupFiles.count, 2)
    }

    // MARK: - Backup Diff Integration

    func testBackupDiffBetweenTwoFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Before: one group with one app
        let beforeExport = SettingsExport(
            groups: [AppGroup(name: "Browsers", apps: [
                AppItem(bundleIdentifier: "com.apple.Safari", name: "Safari")
            ])],
            settings: AppSettings(showHUD: true, showShortcutInHUD: true)
        )
        let beforeData = try encoder.encode(beforeExport)
        try beforeData.write(to: tempDir.appendingPathComponent("backup 2025-01-01 00-00-00.json"))

        // After: same group with added app, changed setting
        let afterExport = SettingsExport(
            groups: [AppGroup(name: "Browsers", apps: [
                AppItem(bundleIdentifier: "com.apple.Safari", name: "Safari"),
                AppItem(bundleIdentifier: "com.google.Chrome", name: "Chrome")
            ])],
            settings: AppSettings(showHUD: false, showShortcutInHUD: true)
        )
        let afterData = try encoder.encode(afterExport)
        try afterData.write(to: tempDir.appendingPathComponent("backup 2025-01-02 00-00-00.json"))

        // Read and decode both
        let before = try decoder.decode(SettingsExport.self, from: beforeData)
        let after = try decoder.decode(SettingsExport.self, from: afterData)

        // Note: groups have different UUIDs since they were created independently,
        // so diff will show old group removed, new group added
        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.settingChanges.count, 1)
        XCTAssertEqual(diff.settingChanges[0].key, "Show HUD")
    }

    // MARK: - Backup File Naming

    func testBackupFileNamingPattern() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "backup \(timestamp).json"

        let export = SettingsExport(groups: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)

        let backupFile = tempDir.appendingPathComponent(filename)
        try data.write(to: backupFile)

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupFile.path))
        XCTAssertTrue(backupFile.lastPathComponent.hasPrefix("backup "))
        XCTAssertEqual(backupFile.pathExtension, "json")
    }

    // MARK: - Empty Backup Directory

    func testEmptyBackupDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let backupFiles = files.filter {
            $0.lastPathComponent.hasPrefix("backup ") && $0.pathExtension == "json"
        }

        XCTAssertTrue(backupFiles.isEmpty)
    }

    // MARK: - Import from Backup

    func testImportFromBackupFile() throws {
        let userDefaults = UserDefaults(suiteName: "TestBackupBrowserImport")!
        userDefaults.removePersistentDomain(forName: "TestBackupBrowserImport")
        let store = GroupStore(userDefaults: userDefaults)
        defer {
            try? FileManager.default.removeItem(at: store.backupDirectory)
            userDefaults.removePersistentDomain(forName: "TestBackupBrowserImport")
        }

        let group = AppGroup(name: "Imported Group", apps: [
            AppItem(bundleIdentifier: "com.imported.app", name: "Imported")
        ])
        let export = SettingsExport(groups: [group])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)

        try store.importData(data)

        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.groups[0].name, "Imported Group")
        XCTAssertEqual(store.groups[0].apps.first?.bundleIdentifier, "com.imported.app")
    }
}

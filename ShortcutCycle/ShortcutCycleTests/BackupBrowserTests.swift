import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

@MainActor
final class BackupBrowserTests: XCTestCase {

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
            // Expected
            break
        }
    }
}

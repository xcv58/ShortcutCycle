import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

/// Tests for type conformances and URL scheme parsing across ShortcutCycleCore
final class ShortcutCycleTests: XCTestCase {

    // MARK: - CyclingAppItem

    func testCyclingAppItemIdentifiable() {
        let item = CyclingAppItem(id: "com.test.app")
        XCTAssertEqual(item.id, "com.test.app")
    }

    func testCyclingAppItemEquatable() {
        let a = CyclingAppItem(id: "com.test.app")
        let b = CyclingAppItem(id: "com.test.app")
        let c = CyclingAppItem(id: "com.other.app")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - ResolvableAppItem

    func testResolvableAppItemProperties() {
        let item = ResolvableAppItem(id: "com.test.app::100", bundleId: "com.test.app")
        XCTAssertEqual(item.id, "com.test.app::100")
        XCTAssertEqual(item.bundleId, "com.test.app")
    }

    // MARK: - DiffStatus

    func testDiffStatusEquatable() {
        XCTAssertEqual(DiffStatus.added, DiffStatus.added)
        XCTAssertEqual(DiffStatus.removed, DiffStatus.removed)
        XCTAssertEqual(DiffStatus.modified, DiffStatus.modified)
        XCTAssertEqual(DiffStatus.unchanged, DiffStatus.unchanged)
        XCTAssertNotEqual(DiffStatus.added, DiffStatus.removed)
    }

    // MARK: - AppCyclingLogic edge case

    func testNextAppIdWithEmptyItems() {
        let result = AppCyclingLogic.nextAppId(
            items: [],
            currentFrontmostAppId: nil,
            currentHUDSelectionId: nil,
            lastActiveAppId: nil,
            isHUDVisible: false
        )
        XCTAssertEqual(result, "")
    }

    func testNextAppIdSingleItem() {
        let items = [CyclingAppItem(id: "com.single.app")]
        let result = AppCyclingLogic.nextAppId(
            items: items,
            currentFrontmostAppId: "com.single.app",
            currentHUDSelectionId: nil,
            lastActiveAppId: nil,
            isHUDVisible: false
        )
        // Single item wraps around to itself
        XCTAssertEqual(result, "com.single.app")
    }

    // MARK: - URL Parser

    func testParseOpenSettingsURL() {
        let url = URL(string: "shortcutcycle://open-settings")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .openSettings(nil))
    }

    func testParseCycleByNameURL() {
        let url = URL(string: "shortcutcycle://cycle?group=Browsers")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .cycle(.name("Browsers")))
    }

    func testParseCycleByUUIDURL() {
        let id = UUID()
        let url = URL(string: "shortcutcycle://cycle?groupId=\(id.uuidString)")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .cycle(.id(id)))
    }

    func testParseSelectGroupRequiresTarget() {
        let url = URL(string: "shortcutcycle://select-group")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseUnsupportedSchemeReturnsNil() {
        let url = URL(string: "https://cycle?group=Browsers")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseXCallbackURL() {
        let url = URL(string: "shortcutcycle://x-callback-url/enable-group?index=2")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .enableGroup(.index(2)))
    }

    func testParseOpenSettingsGeneralTabURL() {
        let url = URL(string: "shortcutcycle://open-settings?tab=general")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .openSettings(.general))
    }

    func testParseOpenBackupBrowserURL() {
        let url = URL(string: "shortcutcycle://open-backup-browser")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .openBackupBrowser)
    }

    func testParseOpenBackupBrowserFromSettingsTabURL() {
        let url = URL(string: "shortcutcycle://open-settings?tab=backup")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .openBackupBrowser)
    }

    func testParseFlushAutoSaveURL() {
        let url = URL(string: "shortcutcycle://flush-auto-save")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .flushAutoSave)
    }

    func testParseSetSettingURL() {
        let url = URL(string: "shortcutcycle://set-setting?key=showHUD&value=true")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .setSetting(key: "showhud", value: "true")
        )
    }

    func testParseExportSettingsURL() {
        let url = URL(string: "shortcutcycle://export-settings?path=/tmp/shortcutcycle-export.json")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .exportSettings(path: "/tmp/shortcutcycle-export.json")
        )
    }

    func testParseExportSettingsWithFileAliasURL() {
        let url = URL(string: "shortcutcycle://export-settings?file=/tmp/shortcutcycle-export.json")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .exportSettings(path: "/tmp/shortcutcycle-export.json")
        )
    }

    func testParseImportSettingsURL() {
        let url = URL(string: "shortcutcycle://import-settings?path=/tmp/shortcutcycle-import.json")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .importSettings(path: "/tmp/shortcutcycle-import.json")
        )
    }

    func testParseRestoreBackupWithoutSelectorUsesLatest() {
        let url = URL(string: "shortcutcycle://restore-backup")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .restoreBackup(nil)
        )
    }

    func testParseRestoreBackupByIndexURL() {
        let url = URL(string: "shortcutcycle://restore-backup?index=2")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .restoreBackup(.index(2))
        )
    }

    func testParseRestoreBackupByNameURL() {
        let url = URL(string: "shortcutcycle://restore-backup?name=backup%202026-03-01%2000-00-00.json")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .restoreBackup(.name("backup 2026-03-01 00-00-00.json"))
        )
    }

    func testParseRestoreBackupByPathURL() {
        let url = URL(string: "shortcutcycle://restore-backup?path=/tmp/backup.json")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .restoreBackup(.path("/tmp/backup.json"))
        )
    }

    func testParseRestoreBackupTargetPrecedencePathOverNameAndIndex() {
        let url = URL(string: "shortcutcycle://restore-backup?index=3&name=backup%20file.json&path=/tmp/backup.json")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .restoreBackup(.path("/tmp/backup.json"))
        )
    }
}

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

    // MARK: - URL Parser: Group CRUD

    func testParseCreateGroupURL() {
        let url = URL(string: "shortcutcycle://create-group?name=Editors")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .createGroup(name: "Editors"))
    }

    func testParseCreateGroupEmptyNameReturnsNil() {
        let url = URL(string: "shortcutcycle://create-group?name=")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseCreateGroupNoNameReturnsNil() {
        let url = URL(string: "shortcutcycle://create-group")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseDeleteGroupURL() {
        let url = URL(string: "shortcutcycle://delete-group?group=Browsers")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .deleteGroup(.name("Browsers")))
    }

    func testParseDeleteGroupRequiresTarget() {
        let url = URL(string: "shortcutcycle://delete-group")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseRenameGroupURL() {
        let url = URL(string: "shortcutcycle://rename-group?group=Browsers&newName=Web")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .renameGroup(.name("Browsers"), newName: "Web"))
    }

    func testParseRenameGroupToAliasURL() {
        let url = URL(string: "shortcutcycle://rename-group?group=Browsers&to=Web")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .renameGroup(.name("Browsers"), newName: "Web"))
    }

    func testParseRenameGroupRequiresNewName() {
        let url = URL(string: "shortcutcycle://rename-group?group=Browsers")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseRenameGroupRequiresTarget() {
        let url = URL(string: "shortcutcycle://rename-group?newName=Web")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseReorderGroupURL() {
        let url = URL(string: "shortcutcycle://reorder-group?group=Browsers&position=1")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .reorderGroup(.name("Browsers"), position: 1))
    }

    func testParseReorderGroupToAliasURL() {
        let url = URL(string: "shortcutcycle://reorder-group?group=Browsers&to=2")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .reorderGroup(.name("Browsers"), position: 2))
    }

    func testParseReorderGroupRequiresPosition() {
        let url = URL(string: "shortcutcycle://reorder-group?group=Browsers")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseReorderGroupRequiresTarget() {
        let url = URL(string: "shortcutcycle://reorder-group?position=1")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseReorderGroupZeroPositionReturnsNil() {
        let url = URL(string: "shortcutcycle://reorder-group?group=Browsers&position=0")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    // MARK: - URL Parser: App Management

    func testParseAddAppURL() {
        let url = URL(string: "shortcutcycle://add-app?group=Browsers&bundleId=com.google.Chrome")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .addApp(.name("Browsers"), bundleId: "com.google.Chrome"))
    }

    func testParseAddAppWithAppAlias() {
        let url = URL(string: "shortcutcycle://add-app?group=Browsers&app=com.google.Chrome")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .addApp(.name("Browsers"), bundleId: "com.google.Chrome"))
    }

    func testParseAddAppWithBundleAlias() {
        let url = URL(string: "shortcutcycle://add-app?group=Browsers&bundle=com.google.Chrome")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .addApp(.name("Browsers"), bundleId: "com.google.Chrome"))
    }

    func testParseAddAppRequiresGroupAndBundleId() {
        let noGroup = URL(string: "shortcutcycle://add-app?bundleId=com.google.Chrome")!
        XCTAssertNil(ShortcutCycleURLParser.parse(noGroup))

        let noBundleId = URL(string: "shortcutcycle://add-app?group=Browsers")!
        XCTAssertNil(ShortcutCycleURLParser.parse(noBundleId))
    }

    func testParseRemoveAppURL() {
        let url = URL(string: "shortcutcycle://remove-app?group=Browsers&bundleId=com.google.Chrome")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .removeApp(.name("Browsers"), bundleId: "com.google.Chrome"))
    }

    func testParseRemoveAppWithAppAlias() {
        let url = URL(string: "shortcutcycle://remove-app?group=Browsers&app=com.google.Chrome")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .removeApp(.name("Browsers"), bundleId: "com.google.Chrome"))
    }

    func testParseRemoveAppWithBundleAlias() {
        let url = URL(string: "shortcutcycle://remove-app?group=Browsers&bundle=com.google.Chrome")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .removeApp(.name("Browsers"), bundleId: "com.google.Chrome"))
    }

    func testParseRemoveAppRequiresGroupAndBundleId() {
        let noGroup = URL(string: "shortcutcycle://remove-app?bundleId=com.google.Chrome")!
        XCTAssertNil(ShortcutCycleURLParser.parse(noGroup))

        let noBundleId = URL(string: "shortcutcycle://remove-app?group=Browsers")!
        XCTAssertNil(ShortcutCycleURLParser.parse(noBundleId))
    }

    // MARK: - URL Parser: Query Commands

    func testParseListGroupsURL() {
        let url = URL(string: "shortcutcycle://list-groups")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .listGroups)
    }

    func testParseListGroupsWithOutputURLIgnoresOutputPath() {
        let url = URL(string: "shortcutcycle://list-groups?output=/tmp/groups.json")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .listGroups)
    }

    func testParseGetGroupURL() {
        let url = URL(string: "shortcutcycle://get-group?group=Browsers")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .getGroup(.name("Browsers")))
    }

    func testParseGetGroupWithOutputURLIgnoresOutputPath() {
        let url = URL(string: "shortcutcycle://get-group?group=Browsers&output=/tmp/detail.json")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .getGroup(.name("Browsers")))
    }

    func testParseGetGroupRequiresTarget() {
        let url = URL(string: "shortcutcycle://get-group")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }
}

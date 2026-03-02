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

    func testQueryResultFileNameConstant() {
        XCTAssertEqual(ShortcutCycleURLParser.queryResultFileName, "shortcutcycle-result.json")
    }

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

    func testParseCycleWithoutTargetReturnsNilGroup() {
        let url = URL(string: "shortcutcycle://cycle")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .cycle(nil))
    }

    func testParseCycleWithInvalidGroupIdReturnsNil() {
        let url = URL(string: "shortcutcycle://cycle?groupId=not-a-uuid&group=Browsers")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseSelectGroupRequiresTarget() {
        let url = URL(string: "shortcutcycle://select-group")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseSelectGroupByNameURL() {
        let url = URL(string: "shortcutcycle://select-group?group=Browsers")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .selectGroup(.name("Browsers")))
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

    func testParseOpenSettingsGroupsTabURL() {
        let url = URL(string: "shortcutcycle://open-settings?tab=group")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .openSettings(.groups))
    }

    func testParseOpenSettingsInvalidTabReturnsNil() {
        let url = URL(string: "shortcutcycle://open-settings?tab=unknown")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseOpenBackupBrowserURL() {
        let url = URL(string: "shortcutcycle://open-backup-browser")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .openBackupBrowser)
    }

    func testParseOpenBackupBrowserFromSettingsTabURL() {
        let url = URL(string: "shortcutcycle://open-settings?tab=backup")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .openBackupBrowser)
    }

    func testParseOpenBackupBrowserFromSettingsSectionURL() {
        let url = URL(string: "shortcutcycle://open-settings?section=backups")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .openBackupBrowser)
    }

    func testParseOpenSettingsWithInvalidSectionReturnsNil() {
        let url = URL(string: "shortcutcycle://open-settings?section=general")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
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

    func testParseSetSettingAliasKeyAndValueURL() {
        let url = URL(string: "shortcutcycle://set-setting?name=showHUD&v=on")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .setSetting(key: "showhud", value: "on")
        )
    }

    func testParseSetSettingMissingValueReturnsNil() {
        let url = URL(string: "shortcutcycle://set-setting?key=showHUD")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseSetSettingWithUnsupportedKeyReturnsNil() {
        let url = URL(string: "shortcutcycle://set-setting?key=unknown&value=true")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseSetSettingWithInvalidBooleanValueReturnsNil() {
        let url = URL(string: "shortcutcycle://set-setting?key=showHUD&value=maybe")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseSetSettingWithInvalidThemeValueReturnsNil() {
        let url = URL(string: "shortcutcycle://set-setting?key=appTheme&value=blue")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseSetSettingWithSelectedLanguageValue() {
        let url = URL(string: "shortcutcycle://set-setting?key=selectedlanguage&value=en")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .setSetting(key: "selectedlanguage", value: "en")
        )
    }

    func testParseSetSettingWithTooLongKeyOrValueReturnsNil() {
        let longKey = String(repeating: "k", count: 129)
        let longValue = String(repeating: "v", count: 129)

        let keyTooLong = URL(string: "shortcutcycle://set-setting?key=\(longKey)&value=true")!
        XCTAssertNil(ShortcutCycleURLParser.parse(keyTooLong))

        let valueTooLong = URL(string: "shortcutcycle://set-setting?key=showHUD&value=\(longValue)")!
        XCTAssertNil(ShortcutCycleURLParser.parse(valueTooLong))
    }

    func testParseBackupURL() {
        let url = URL(string: "shortcutcycle://backup")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .backup)
    }

    func testParseExportSettingsURL() {
        let url = URL(string: "shortcutcycle://export-settings?path=/tmp/shortcutcycle-export.json")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .exportSettings(path: "/tmp/shortcutcycle-export.json")
        )
    }

    func testParseExportSettingsWithoutPathUsesDefaultLocation() {
        let url = URL(string: "shortcutcycle://export-settings")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .exportSettings(path: nil)
        )
    }

    func testParseExportSettingsWithFileAliasURL() {
        let url = URL(string: "shortcutcycle://export-settings?file=/tmp/shortcutcycle-export.json")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .exportSettings(path: "/tmp/shortcutcycle-export.json")
        )
    }

    func testParseExportSettingsWithEmptyPathReturnsNil() {
        let url = URL(string: "shortcutcycle://export-settings?path=")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseImportSettingsURL() {
        let url = URL(string: "shortcutcycle://import-settings?path=/tmp/shortcutcycle-import.json")!
        XCTAssertEqual(
            ShortcutCycleURLParser.parse(url),
            .importSettings(path: "/tmp/shortcutcycle-import.json")
        )
    }

    func testParseImportSettingsWithEmptyPathReturnsNil() {
        let url = URL(string: "shortcutcycle://import-settings?path=")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseImportSettingsWithTooLongPathReturnsNil() {
        let longPath = "/" + String(repeating: "a", count: 1025)
        let url = URL(string: "shortcutcycle://import-settings?path=\(longPath)")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
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

    func testParseRestoreBackupWithInvalidIndexReturnsNil() {
        let zero = URL(string: "shortcutcycle://restore-backup?index=0")!
        XCTAssertNil(ShortcutCycleURLParser.parse(zero))

        let negative = URL(string: "shortcutcycle://restore-backup?backupindex=-1")!
        XCTAssertNil(ShortcutCycleURLParser.parse(negative))

        let nonNumeric = URL(string: "shortcutcycle://restore-backup?index=abc")!
        XCTAssertNil(ShortcutCycleURLParser.parse(nonNumeric))
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

    func testParseRestoreBackupWithEmptyPathReturnsNil() {
        let url = URL(string: "shortcutcycle://restore-backup?path=")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseRestoreBackupWithEmptyNameReturnsNil() {
        let url = URL(string: "shortcutcycle://restore-backup?name=")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseRestoreBackupWithTooLongNameReturnsNil() {
        let longName = String(repeating: "b", count: 256) + ".json"
        let url = URL(string: "shortcutcycle://restore-backup?name=\(longName)")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
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

    func testParseCreateGroupTooLongNameReturnsNil() {
        let longName = String(repeating: "g", count: 256)
        let url = URL(string: "shortcutcycle://create-group?name=\(longName)")!
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

    func testParseDeleteGroupInvalidIndexDoesNotFallBackToName() {
        let url = URL(string: "shortcutcycle://delete-group?index=0&group=Browsers")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseDisableGroupURL() {
        let url = URL(string: "shortcutcycle://disable-group?group=Browsers")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .disableGroup(.name("Browsers")))
    }

    func testParseToggleGroupURL() {
        let url = URL(string: "shortcutcycle://toggle-group?group=Browsers")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .toggleGroup(.name("Browsers")))
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

    func testParseAddAppInvalidGroupIdDoesNotFallBackToName() {
        let url = URL(string: "shortcutcycle://add-app?id=not-a-uuid&group=Browsers&bundleId=com.google.Chrome")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseAddAppWithTooLongBundleIdReturnsNil() {
        let longBundle = String(repeating: "a", count: 256)
        let url = URL(string: "shortcutcycle://add-app?group=Browsers&bundleId=\(longBundle)")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
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

    func testParseListGroupsWithValuelessQueryItem() {
        let url = URL(string: "shortcutcycle://list-groups?output")!
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

    func testParseGetGroupInvalidGroupIdDoesNotFallBackToName() {
        let url = URL(string: "shortcutcycle://get-group?id=not-a-uuid&group=Browsers")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseUnknownActionReturnsNil() {
        let url = URL(string: "shortcutcycle://not-a-command")!
        XCTAssertNil(ShortcutCycleURLParser.parse(url))
    }

    func testParseActionFromPathWhenHostMissing() {
        let url = URL(string: "shortcutcycle:///cycle?group=Browsers")!
        XCTAssertEqual(ShortcutCycleURLParser.parse(url), .cycle(.name("Browsers")))
    }
}

import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

final class BackupDiffTests: XCTestCase {

    // MARK: - Helpers

    private func makeApp(_ bundleId: String, name: String? = nil) -> AppItem {
        AppItem(bundleIdentifier: bundleId, name: name ?? bundleId)
    }

    private func makeGroup(id: UUID = UUID(), name: String, apps: [AppItem] = []) -> AppGroup {
        AppGroup(id: id, name: name, apps: apps)
    }

    private func makeExport(
        groups: [AppGroup],
        settings: AppSettings? = nil
    ) -> SettingsExport {
        SettingsExport(groups: groups, settings: settings)
    }

    // MARK: - No Changes

    func testIdenticalSnapshotsHaveNoChanges() {
        let groupId = UUID()
        let app = makeApp("com.test.app", name: "Test")
        let groups = [makeGroup(id: groupId, name: "Group", apps: [app])]
        let settings = AppSettings(showHUD: true, showShortcutInHUD: true)

        let before = makeExport(groups: groups, settings: settings)
        let after = makeExport(groups: groups, settings: settings)

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertFalse(diff.hasChanges)
        XCTAssertTrue(diff.settingChanges.isEmpty)
        XCTAssertTrue(diff.groupDiffs.allSatisfy { $0.status == .unchanged })
    }

    func testEmptySnapshotsHaveNoChanges() {
        let before = makeExport(groups: [])
        let after = makeExport(groups: [])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertFalse(diff.hasChanges)
        XCTAssertTrue(diff.groupDiffs.isEmpty)
        XCTAssertTrue(diff.settingChanges.isEmpty)
    }

    // MARK: - Group Additions

    func testAddedGroupDetected() {
        let before = makeExport(groups: [])
        let newGroup = makeGroup(name: "New Group", apps: [makeApp("com.app.a")])
        let after = makeExport(groups: [newGroup])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.groupDiffs.count, 1)
        XCTAssertEqual(diff.groupDiffs[0].status, .added)
        XCTAssertEqual(diff.groupDiffs[0].groupName, "New Group")
        XCTAssertEqual(diff.groupDiffs[0].appChanges.count, 1)
        XCTAssertEqual(diff.groupDiffs[0].appChanges[0].status, .added)
    }

    // MARK: - Group Removals

    func testRemovedGroupDetected() {
        let oldGroup = makeGroup(name: "Old Group", apps: [makeApp("com.app.a")])
        let before = makeExport(groups: [oldGroup])
        let after = makeExport(groups: [])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.groupDiffs.count, 1)
        XCTAssertEqual(diff.groupDiffs[0].status, .removed)
        XCTAssertEqual(diff.groupDiffs[0].groupName, "Old Group")
        XCTAssertEqual(diff.groupDiffs[0].appChanges.count, 1)
        XCTAssertEqual(diff.groupDiffs[0].appChanges[0].status, .removed)
    }

    // MARK: - Group Modifications

    func testGroupNameChangeDetected() {
        let groupId = UUID()
        let app = makeApp("com.app.a")
        let before = makeExport(groups: [makeGroup(id: groupId, name: "Old Name", apps: [app])])
        let after = makeExport(groups: [makeGroup(id: groupId, name: "New Name", apps: [app])])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.groupDiffs.count, 1)
        XCTAssertEqual(diff.groupDiffs[0].status, .modified)
        XCTAssertEqual(diff.groupDiffs[0].groupName, "New Name")
    }

    func testAppAddedToGroupDetected() {
        let groupId = UUID()
        let existingApp = makeApp("com.app.a")
        let newApp = makeApp("com.app.b", name: "App B")
        let before = makeExport(groups: [makeGroup(id: groupId, name: "Group", apps: [existingApp])])
        let after = makeExport(groups: [makeGroup(id: groupId, name: "Group", apps: [existingApp, newApp])])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.groupDiffs[0].status, .modified)

        let appChanges = diff.groupDiffs[0].appChanges
        XCTAssertEqual(appChanges.count, 2)
        XCTAssertTrue(appChanges.contains(where: { $0.bundleIdentifier == "com.app.a" && $0.status == .unchanged }))
        XCTAssertTrue(appChanges.contains(where: { $0.bundleIdentifier == "com.app.b" && $0.status == .added }))
    }

    func testAppRemovedFromGroupDetected() {
        let groupId = UUID()
        let app1 = makeApp("com.app.a")
        let app2 = makeApp("com.app.b")
        let before = makeExport(groups: [makeGroup(id: groupId, name: "Group", apps: [app1, app2])])
        let after = makeExport(groups: [makeGroup(id: groupId, name: "Group", apps: [app1])])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.groupDiffs[0].status, .modified)

        let appChanges = diff.groupDiffs[0].appChanges
        XCTAssertTrue(appChanges.contains(where: { $0.bundleIdentifier == "com.app.a" && $0.status == .unchanged }))
        XCTAssertTrue(appChanges.contains(where: { $0.bundleIdentifier == "com.app.b" && $0.status == .removed }))
    }

    func testUnchangedGroupAppsAllUnchanged() {
        let groupId = UUID()
        let apps = [makeApp("com.app.a"), makeApp("com.app.b")]
        let before = makeExport(groups: [makeGroup(id: groupId, name: "Group", apps: apps)])
        let after = makeExport(groups: [makeGroup(id: groupId, name: "Group", apps: apps)])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertFalse(diff.hasChanges)
        XCTAssertEqual(diff.groupDiffs[0].status, .unchanged)
        XCTAssertTrue(diff.groupDiffs[0].appChanges.allSatisfy { $0.status == .unchanged })
    }

    // MARK: - Multiple Group Changes

    func testMultipleGroupChanges() {
        let keepId = UUID()
        let removeId = UUID()
        let addId = UUID()

        let keepApp = makeApp("com.keep.app")
        let removeApp = makeApp("com.remove.app")
        let addApp = makeApp("com.add.app")

        let before = makeExport(groups: [
            makeGroup(id: keepId, name: "Keep", apps: [keepApp]),
            makeGroup(id: removeId, name: "Remove", apps: [removeApp])
        ])
        let after = makeExport(groups: [
            makeGroup(id: keepId, name: "Keep", apps: [keepApp]),
            makeGroup(id: addId, name: "Added", apps: [addApp])
        ])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.groupDiffs.count, 3)

        let unchanged = diff.groupDiffs.first(where: { $0.id == keepId })
        let removed = diff.groupDiffs.first(where: { $0.id == removeId })
        let added = diff.groupDiffs.first(where: { $0.id == addId })

        XCTAssertEqual(unchanged?.status, .unchanged)
        XCTAssertEqual(removed?.status, .removed)
        XCTAssertEqual(added?.status, .added)
    }

    // MARK: - Settings Changes

    func testShowHUDSettingChange() {
        let before = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true))
        let after = makeExport(groups: [], settings: AppSettings(showHUD: false, showShortcutInHUD: true))

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.settingChanges.count, 1)
        XCTAssertEqual(diff.settingChanges[0].key, "Show HUD")
        XCTAssertEqual(diff.settingChanges[0].oldValue, "true")
        XCTAssertEqual(diff.settingChanges[0].newValue, "false")
    }

    func testShowShortcutInHUDSettingChange() {
        let before = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true))
        let after = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: false))

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.settingChanges.count, 1)
        XCTAssertEqual(diff.settingChanges[0].key, "Show Shortcut in HUD")
    }

    func testLanguageSettingChange() {
        let before = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true, selectedLanguage: "en"))
        let after = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true, selectedLanguage: "ja"))

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.settingChanges.count, 1)
        XCTAssertEqual(diff.settingChanges[0].key, "Language")
        XCTAssertEqual(diff.settingChanges[0].oldValue, "en")
        XCTAssertEqual(diff.settingChanges[0].newValue, "ja")
    }

    func testThemeSettingChange() {
        let before = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true, appTheme: "light"))
        let after = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true, appTheme: "dark"))

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.settingChanges.count, 1)
        XCTAssertEqual(diff.settingChanges[0].key, "Theme")
        XCTAssertEqual(diff.settingChanges[0].oldValue, "light")
        XCTAssertEqual(diff.settingChanges[0].newValue, "dark")
    }

    func testMultipleSettingsChanged() {
        let before = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true, selectedLanguage: "en", appTheme: "light"))
        let after = makeExport(groups: [], settings: AppSettings(showHUD: false, showShortcutInHUD: false, selectedLanguage: "ja", appTheme: "dark"))

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.settingChanges.count, 4)
    }

    func testNoSettingsChange() {
        let settings = AppSettings(showHUD: true, showShortcutInHUD: false, selectedLanguage: "en", appTheme: "dark")
        let before = makeExport(groups: [], settings: settings)
        let after = makeExport(groups: [], settings: settings)

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.settingChanges.isEmpty)
    }

    // MARK: - Nil Settings Handling

    func testNilBeforeSettingsUsesDefaults() {
        let before = makeExport(groups: [], settings: nil)
        let after = makeExport(groups: [], settings: AppSettings(showHUD: false, showShortcutInHUD: true))

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.settingChanges.count, 1)
        XCTAssertEqual(diff.settingChanges[0].key, "Show HUD")
    }

    func testNilAfterSettingsUsesDefaults() {
        let before = makeExport(groups: [], settings: AppSettings(showHUD: false, showShortcutInHUD: true))
        let after = makeExport(groups: [], settings: nil)

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.settingChanges.count, 1)
        XCTAssertEqual(diff.settingChanges[0].key, "Show HUD")
    }

    func testBothNilSettingsNoChanges() {
        let before = makeExport(groups: [], settings: nil)
        let after = makeExport(groups: [], settings: nil)

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.settingChanges.isEmpty)
    }

    func testNilLanguageTreatedAsSystem() {
        let before = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true, selectedLanguage: nil))
        let after = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true, selectedLanguage: "system"))

        let diff = BackupDiff.compute(before: before, after: after)

        // nil and "system" should be treated the same
        XCTAssertTrue(diff.settingChanges.isEmpty)
    }

    func testNilThemeTreatedAsSystem() {
        let before = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true, appTheme: nil))
        let after = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true, appTheme: "system"))

        let diff = BackupDiff.compute(before: before, after: after)

        // nil and "system" should be treated the same
        XCTAssertTrue(diff.settingChanges.isEmpty)
    }

    // MARK: - Combined Group and Settings Changes

    func testGroupAndSettingsChangesBothDetected() {
        let groupId = UUID()
        let before = makeExport(
            groups: [makeGroup(id: groupId, name: "Old", apps: [])],
            settings: AppSettings(showHUD: true, showShortcutInHUD: true)
        )
        let after = makeExport(
            groups: [makeGroup(id: groupId, name: "New", apps: [])],
            settings: AppSettings(showHUD: false, showShortcutInHUD: true)
        )

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.groupDiffs[0].status, .modified)
        XCTAssertEqual(diff.settingChanges.count, 1)
    }

    // MARK: - hasChanges Property

    func testHasChangesIsFalseWhenAllUnchanged() {
        let groupId = UUID()
        let groups = [makeGroup(id: groupId, name: "G", apps: [])]
        let settings = AppSettings(showHUD: true, showShortcutInHUD: true)

        let diff = BackupDiff.compute(
            before: makeExport(groups: groups, settings: settings),
            after: makeExport(groups: groups, settings: settings)
        )

        XCTAssertFalse(diff.hasChanges)
    }

    func testHasChangesIsTrueForGroupChangeOnly() {
        let before = makeExport(groups: [])
        let after = makeExport(groups: [makeGroup(name: "New")])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
    }

    func testHasChangesIsTrueForSettingChangeOnly() {
        let before = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true))
        let after = makeExport(groups: [], settings: AppSettings(showHUD: false, showShortcutInHUD: true))

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
    }

    // MARK: - Edge Cases

    func testGroupWithEmptyAppList() {
        let groupId = UUID()
        let before = makeExport(groups: [makeGroup(id: groupId, name: "Empty", apps: [])])
        let after = makeExport(groups: [makeGroup(id: groupId, name: "Empty", apps: [])])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertFalse(diff.hasChanges)
        XCTAssertEqual(diff.groupDiffs[0].appChanges.count, 0)
    }

    func testAllAppsReplacedInGroup() {
        let groupId = UUID()
        let before = makeExport(groups: [makeGroup(id: groupId, name: "G", apps: [makeApp("com.old.a"), makeApp("com.old.b")])])
        let after = makeExport(groups: [makeGroup(id: groupId, name: "G", apps: [makeApp("com.new.x"), makeApp("com.new.y")])])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertTrue(diff.hasChanges)
        let changes = diff.groupDiffs[0].appChanges
        let added = changes.filter { $0.status == .added }
        let removed = changes.filter { $0.status == .removed }
        XCTAssertEqual(added.count, 2)
        XCTAssertEqual(removed.count, 2)
    }

    // MARK: - AppChange and GroupDiff Properties

    func testAppChangePropertiesArePopulated() {
        let groupId = UUID()
        let before = makeExport(groups: [makeGroup(id: groupId, name: "G", apps: [makeApp("com.old", name: "Old App")])])
        let after = makeExport(groups: [makeGroup(id: groupId, name: "G", apps: [makeApp("com.new", name: "New App")])])

        let diff = BackupDiff.compute(before: before, after: after)

        let added = diff.groupDiffs[0].appChanges.first(where: { $0.status == .added })
        XCTAssertEqual(added?.appName, "New App")
        XCTAssertEqual(added?.bundleIdentifier, "com.new")
        XCTAssertNotNil(added?.id)

        let removed = diff.groupDiffs[0].appChanges.first(where: { $0.status == .removed })
        XCTAssertEqual(removed?.appName, "Old App")
        XCTAssertEqual(removed?.bundleIdentifier, "com.old")
    }

    func testGroupDiffPropertiesArePopulated() {
        let groupId = UUID()
        let before = makeExport(groups: [makeGroup(id: groupId, name: "Group Name", apps: [])])
        let after = makeExport(groups: [makeGroup(id: groupId, name: "Group Name", apps: [])])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertEqual(diff.groupDiffs[0].id, groupId)
        XCTAssertEqual(diff.groupDiffs[0].groupName, "Group Name")
        XCTAssertEqual(diff.groupDiffs[0].status, .unchanged)
        XCTAssertEqual(diff.groupDiffs[0].appChanges.count, 0)
    }

    func testSettingChangePropertiesArePopulated() {
        let before = makeExport(groups: [], settings: AppSettings(showHUD: true, showShortcutInHUD: true))
        let after = makeExport(groups: [], settings: AppSettings(showHUD: false, showShortcutInHUD: true))

        let diff = BackupDiff.compute(before: before, after: after)

        let change = diff.settingChanges[0]
        XCTAssertNotNil(change.id)
        XCTAssertEqual(change.key, "Show HUD")
        XCTAssertEqual(change.oldValue, "true")
        XCTAssertEqual(change.newValue, "false")
    }

    func testAddedGroupWithEmptyApps() {
        let before = makeExport(groups: [])
        let after = makeExport(groups: [makeGroup(name: "Empty New")])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertEqual(diff.groupDiffs[0].status, .added)
        XCTAssertEqual(diff.groupDiffs[0].appChanges.count, 0)
    }

    func testRemovedGroupWithEmptyApps() {
        let before = makeExport(groups: [makeGroup(name: "Empty Old")])
        let after = makeExport(groups: [])

        let diff = BackupDiff.compute(before: before, after: after)

        XCTAssertEqual(diff.groupDiffs[0].status, .removed)
        XCTAssertEqual(diff.groupDiffs[0].appChanges.count, 0)
    }

    // MARK: - hasChanges with unchanged groups but no settings

    func testHasChangesNoSettingsNoGroupChanges() {
        let groupId = UUID()
        let diff = BackupDiff.compute(
            before: makeExport(groups: [makeGroup(id: groupId, name: "G")]),
            after: makeExport(groups: [makeGroup(id: groupId, name: "G")])
        )

        XCTAssertFalse(diff.hasChanges)
        XCTAssertTrue(diff.settingChanges.isEmpty)
    }
}

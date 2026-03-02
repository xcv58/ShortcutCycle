import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

final class URLRouterLogicTests: XCTestCase {

    // MARK: - parseBool

    func testParseBoolTrueValues() {
        for input in ["1", "true", "yes", "on", "enabled"] {
            XCTAssertEqual(URLRouterLogic.parseBool(input), true, "Expected true for \"\(input)\"")
        }
    }

    func testParseBoolFalseValues() {
        for input in ["0", "false", "no", "off", "disabled"] {
            XCTAssertEqual(URLRouterLogic.parseBool(input), false, "Expected false for \"\(input)\"")
        }
    }

    func testParseBoolCaseInsensitiveAndWhitespace() {
        XCTAssertEqual(URLRouterLogic.parseBool(" TRUE "), true)
        XCTAssertEqual(URLRouterLogic.parseBool(" False "), false)
        XCTAssertEqual(URLRouterLogic.parseBool("YES"), true)
        XCTAssertEqual(URLRouterLogic.parseBool("OFF"), false)
    }

    func testParseBoolInvalidValues() {
        XCTAssertNil(URLRouterLogic.parseBool("maybe"))
        XCTAssertNil(URLRouterLogic.parseBool(""))
        XCTAssertNil(URLRouterLogic.parseBool("2"))
        XCTAssertNil(URLRouterLogic.parseBool("nope"))
    }

    // MARK: - parseTheme

    func testParseThemeValidValues() {
        XCTAssertEqual(URLRouterLogic.parseTheme("system"), "system")
        XCTAssertEqual(URLRouterLogic.parseTheme("light"), "light")
        XCTAssertEqual(URLRouterLogic.parseTheme("dark"), "dark")
        XCTAssertEqual(URLRouterLogic.parseTheme("default"), "system")
    }

    func testParseThemeCaseInsensitive() {
        XCTAssertEqual(URLRouterLogic.parseTheme("DARK"), "dark")
        XCTAssertEqual(URLRouterLogic.parseTheme("Light"), "light")
        XCTAssertEqual(URLRouterLogic.parseTheme(" System "), "system")
    }

    func testParseThemeInvalidValues() {
        XCTAssertNil(URLRouterLogic.parseTheme("auto"))
        XCTAssertNil(URLRouterLogic.parseTheme(""))
        XCTAssertNil(URLRouterLogic.parseTheme("sepia"))
    }

    // MARK: - parseLanguage

    private let supportedCodes = ["en", "de", "fr", "es", "it", "pt-BR", "ja", "ko", "zh-Hans", "zh-Hant", "ar", "nl", "pl", "tr", "ru"]

    func testParseLanguageSystemValue() {
        XCTAssertEqual(URLRouterLogic.parseLanguage("system", supportedCodes: supportedCodes), "system")
        XCTAssertEqual(URLRouterLogic.parseLanguage("SYSTEM", supportedCodes: supportedCodes), "system")
        XCTAssertEqual(URLRouterLogic.parseLanguage(" System ", supportedCodes: supportedCodes), "system")
    }

    func testParseLanguageCanonicalCasing() {
        XCTAssertEqual(URLRouterLogic.parseLanguage("PT-BR", supportedCodes: supportedCodes), "pt-BR")
        XCTAssertEqual(URLRouterLogic.parseLanguage("ZH-HANS", supportedCodes: supportedCodes), "zh-Hans")
        XCTAssertEqual(URLRouterLogic.parseLanguage("zh-hant", supportedCodes: supportedCodes), "zh-Hant")
    }

    func testParseLanguageSimpleCode() {
        XCTAssertEqual(URLRouterLogic.parseLanguage("en", supportedCodes: supportedCodes), "en")
        XCTAssertEqual(URLRouterLogic.parseLanguage("DE", supportedCodes: supportedCodes), "de")
    }

    func testParseLanguageInvalidValues() {
        XCTAssertNil(URLRouterLogic.parseLanguage("xx", supportedCodes: supportedCodes))
        XCTAssertNil(URLRouterLogic.parseLanguage("", supportedCodes: supportedCodes))
        XCTAssertNil(URLRouterLogic.parseLanguage("english", supportedCodes: supportedCodes))
    }

    // MARK: - resolveGroup

    private func makeGroup(name: String, isEnabled: Bool = true, id: UUID = UUID()) -> AppGroup {
        AppGroup(id: id, name: name, apps: [], isEnabled: isEnabled)
    }

    func testResolveGroupNilTargetReturnsSelectedIfEnabled() {
        let selected = makeGroup(name: "Selected")
        let other = makeGroup(name: "Other")
        let result = URLRouterLogic.resolveGroup(nil, groups: [other, selected], selectedGroup: selected)
        XCTAssertEqual(result?.id, selected.id)
    }

    func testResolveGroupNilTargetFallsToFirstEnabledWhenSelectedDisabled() {
        let disabled = makeGroup(name: "Disabled", isEnabled: false)
        let enabled = makeGroup(name: "Enabled")
        let result = URLRouterLogic.resolveGroup(nil, groups: [disabled, enabled], selectedGroup: disabled)
        XCTAssertEqual(result?.id, enabled.id)
    }

    func testResolveGroupNilTargetReturnsNilWhenNoGroups() {
        let result = URLRouterLogic.resolveGroup(nil, groups: [], selectedGroup: nil)
        XCTAssertNil(result)
    }

    func testResolveGroupById() {
        let target = UUID()
        let group = makeGroup(name: "Match", id: target)
        let other = makeGroup(name: "Other")
        let result = URLRouterLogic.resolveGroup(.id(target), groups: [other, group], selectedGroup: nil)
        XCTAssertEqual(result?.id, target)
    }

    func testResolveGroupByIdNotFound() {
        let group = makeGroup(name: "Group")
        let result = URLRouterLogic.resolveGroup(.id(UUID()), groups: [group], selectedGroup: nil)
        XCTAssertNil(result)
    }

    func testResolveGroupByNameCaseAndDiacriticInsensitive() {
        let group = makeGroup(name: "Caf\u{00E9}")
        let result = URLRouterLogic.resolveGroup(.name("cafe"), groups: [group], selectedGroup: nil)
        XCTAssertEqual(result?.id, group.id)
    }

    func testResolveGroupByIndex() {
        let first = makeGroup(name: "First")
        let second = makeGroup(name: "Second")
        let groups = [first, second]

        XCTAssertEqual(URLRouterLogic.resolveGroup(.index(1), groups: groups, selectedGroup: nil)?.id, first.id)
        XCTAssertEqual(URLRouterLogic.resolveGroup(.index(2), groups: groups, selectedGroup: nil)?.id, second.id)
    }

    func testResolveGroupByIndexOutOfRange() {
        let group = makeGroup(name: "Only")
        XCTAssertNil(URLRouterLogic.resolveGroup(.index(0), groups: [group], selectedGroup: nil))
        XCTAssertNil(URLRouterLogic.resolveGroup(.index(999), groups: [group], selectedGroup: nil))
    }

    // MARK: - Error Message Formatters

    func testExportPathErrorMessages() {
        let home = "/Users/test"
        let emptyMsg = URLRouterLogic.exportPathErrorMessage(for: .emptyPath, home: home)
        XCTAssertTrue(emptyMsg.contains("Invalid export path"))
        XCTAssertTrue(emptyMsg.contains("non-empty"))

        let outsideMsg = URLRouterLogic.exportPathErrorMessage(for: .pathOutsideContainer, home: home)
        XCTAssertTrue(outsideMsg.contains(home))

        let otherMsg = URLRouterLogic.exportPathErrorMessage(for: .invalidBackupName, home: home)
        XCTAssertTrue(otherMsg.contains("Invalid export path"))
    }

    func testImportPathErrorMessages() {
        let home = "/Users/test"
        let emptyMsg = URLRouterLogic.importPathErrorMessage(for: .emptyPath, home: home)
        XCTAssertTrue(emptyMsg.contains("Invalid import path"))

        let outsideMsg = URLRouterLogic.importPathErrorMessage(for: .pathOutsideContainer, home: home)
        XCTAssertTrue(outsideMsg.contains(home))

        let otherMsg = URLRouterLogic.importPathErrorMessage(for: .invalidBackupName, home: home)
        XCTAssertTrue(otherMsg.contains("Invalid import path"))
    }

    func testBackupTargetErrorMessages() {
        let home = "/Users/test"
        let emptyMsg = URLRouterLogic.backupTargetErrorMessage(for: .emptyPath, home: home)
        XCTAssertTrue(emptyMsg.contains("Invalid backup path"))

        let outsideMsg = URLRouterLogic.backupTargetErrorMessage(for: .pathOutsideContainer, home: home)
        XCTAssertTrue(outsideMsg.contains(home))

        let nameMsg = URLRouterLogic.backupTargetErrorMessage(for: .invalidBackupName, home: home)
        XCTAssertTrue(nameMsg.contains("filename"))

        let dirMsg = URLRouterLogic.backupTargetErrorMessage(for: .backupOutsideDirectory, home: home)
        XCTAssertTrue(dirMsg.contains("automatic backup directory"))

        let indexMsg = URLRouterLogic.backupTargetErrorMessage(for: .backupIndexOutOfRange, home: home)
        XCTAssertTrue(indexMsg.contains("out of range"))

        let noneMsg = URLRouterLogic.backupTargetErrorMessage(for: .noBackupsAvailable, home: home)
        XCTAssertTrue(noneMsg.contains("No backup files"))
    }
}

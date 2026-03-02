import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

final class URLCommandFileValidationTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        let fm = FileManager.default
        for url in temporaryURLs {
            try? fm.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        super.tearDown()
    }

    func testValidateBackupNameRejectsTraversalAndSeparators() {
        XCTAssertFalse(URLCommandFileValidation.validateBackupName("../evil.json"))
        XCTAssertFalse(URLCommandFileValidation.validateBackupName("..\\evil.json"))
        XCTAssertFalse(URLCommandFileValidation.validateBackupName("nested/evil.json"))
        XCTAssertFalse(URLCommandFileValidation.validateBackupName("nested\\evil.json"))
        XCTAssertFalse(URLCommandFileValidation.validateBackupName("safe..json"))
        XCTAssertTrue(URLCommandFileValidation.validateBackupName("backup 2026-03-01 00-00-00.json"))
    }

    func testValidationErrorDescriptionsCoverAllCases() {
        let cases: [URLCommandFileValidation.ValidationError] = [
            .emptyPath,
            .invalidPath,
            .pathOutsideContainer,
            .invalidBackupName,
            .backupOutsideDirectory,
            .backupIndexOutOfRange,
            .noBackupsAvailable
        ]

        for error in cases {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }

    func testNormalizedFileURLAcceptsFileURLInput() {
        let home = makeTempDirectory(name: "home")
        let file = home.appendingPathComponent("tmp/settings.json")
        makeFile(file, contents: "{}")

        let normalized = URLCommandFileValidation.normalizedFileURL(rawPath: file.absoluteString)
        guard let normalized else {
            return XCTFail("Expected normalized URL for file URL input")
        }
        XCTAssertEqual(canonicalPath(normalized), canonicalPath(file))
    }

    func testCreationDateReturnsDistantPastForMissingFile() {
        let home = makeTempDirectory(name: "home")
        let missingFile = home.appendingPathComponent("missing.json")
        XCTAssertEqual(
            URLCommandFileValidation.creationDate(for: missingFile),
            .distantPast
        )
    }

    func testCreationDateReturnsNonDefaultForExistingFile() {
        let home = makeTempDirectory(name: "home")
        let existingFile = home.appendingPathComponent("backup.json")
        makeFile(existingFile, contents: "{}")
        XCTAssertNotEqual(
            URLCommandFileValidation.creationDate(for: existingFile),
            .distantPast
        )
    }

    func testValidateImportURLRejectsPathOutsideContainer() {
        let home = makeTempDirectory(name: "home")
        let outside = makeTempDirectory(name: "outside")
        let outsideFile = outside.appendingPathComponent("settings.json")
        makeFile(outsideFile, contents: "{}")

        let result = URLCommandFileValidation.validateImportURL(
            rawPath: outsideFile.path,
            home: home
        )
        XCTAssertFailure(result, expected: .pathOutsideContainer)
    }

    func testValidateImportURLAcceptsPathInsideContainer() {
        let home = makeTempDirectory(name: "home")
        let insideFile = home.appendingPathComponent("tmp/settings.json")
        makeFile(insideFile, contents: "{}")

        let result = URLCommandFileValidation.validateImportURL(
            rawPath: insideFile.path,
            home: home
        )
        guard case .success(let url) = result else {
            return XCTFail("Expected success for path inside container")
        }
        XCTAssertEqual(canonicalPath(url), canonicalPath(insideFile))
    }

    func testValidateImportURLRejectsRelativeTraversalEscape() {
        let home = makeTempDirectory(name: "home")
        let cwd = home.appendingPathComponent("tmp", isDirectory: true)
        let outside = makeTempDirectory(name: "outside")
        makeDirectory(cwd)

        let result = URLCommandFileValidation.validateImportURL(
            rawPath: "../../\(outside.lastPathComponent)/settings.json",
            home: home,
            cwd: cwd
        )
        XCTAssertFailure(result, expected: .pathOutsideContainer)
    }

    func testValidateImportURLRejectsNonFileScheme() {
        let home = makeTempDirectory(name: "home")
        let result = URLCommandFileValidation.validateImportURL(
            rawPath: "https://example.com/settings.json",
            home: home
        )
        XCTAssertFailure(result, expected: .invalidPath)
    }

    func testIsDescendantRejectsSymlinkEscape() {
        let home = makeTempDirectory(name: "home")
        let outside = makeTempDirectory(name: "outside")
        let outsideFile = outside.appendingPathComponent("settings.json")
        makeFile(outsideFile, contents: "{}")
        let link = home.appendingPathComponent("link", isDirectory: true)
        do {
            try FileManager.default.createSymbolicLink(
                atPath: link.path,
                withDestinationPath: outside.path
            )
        } catch {
            return XCTFail("Expected symlink creation to succeed: \(error)")
        }

        let escapedFile = link.appendingPathComponent(outsideFile.lastPathComponent)
        XCTAssertFalse(URLCommandFileValidation.isDescendant(candidate: escapedFile, root: home))
    }

    func testResolveBackupURLByNameRejectsTraversal() {
        let home = makeTempDirectory(name: "home")
        let backupDir = home.appendingPathComponent("Library/Application Support/ShortcutCycle", isDirectory: true)
        makeDirectory(backupDir)

        let result = URLCommandFileValidation.resolveBackupURL(
            target: .name("../evil.json"),
            backupDirectory: backupDir,
            home: home
        )
        XCTAssertFailure(result, expected: .invalidBackupName)
    }

    func testResolveBackupURLByNameAcceptsSimpleFilename() {
        let home = makeTempDirectory(name: "home")
        let backupDir = home.appendingPathComponent("Library/Application Support/ShortcutCycle", isDirectory: true)
        makeDirectory(backupDir)
        let backupName = "backup 2026-03-03 00-00-00.json"
        let backupFile = backupDir.appendingPathComponent(backupName)
        makeFile(backupFile, contents: "{}")

        let result = URLCommandFileValidation.resolveBackupURL(
            target: .name(backupName),
            backupDirectory: backupDir,
            home: home
        )
        guard case .success(let url) = result else {
            return XCTFail("Expected success for valid backup name")
        }
        XCTAssertEqual(canonicalPath(url), canonicalPath(backupFile))
    }

    func testResolveBackupURLByNameRejectsSymlinkEscapingBackupDirectory() {
        let home = makeTempDirectory(name: "home")
        let backupDir = home.appendingPathComponent("Library/Application Support/ShortcutCycle", isDirectory: true)
        makeDirectory(backupDir)
        let outside = makeTempDirectory(name: "outside")
        let outsideFile = outside.appendingPathComponent("backup.json")
        makeFile(outsideFile, contents: "{}")
        let symlinkName = "backup-link.json"
        let symlinkURL = backupDir.appendingPathComponent(symlinkName)
        do {
            try FileManager.default.createSymbolicLink(
                atPath: symlinkURL.path,
                withDestinationPath: outsideFile.path
            )
        } catch {
            return XCTFail("Expected backup symlink creation to succeed: \(error)")
        }

        let result = URLCommandFileValidation.resolveBackupURL(
            target: .name(symlinkName),
            backupDirectory: backupDir,
            home: home
        )
        XCTAssertFailure(result, expected: .backupOutsideDirectory)
    }

    func testResolveBackupURLByPathRejectsOutsideContainer() {
        let home = makeTempDirectory(name: "home")
        let backupDir = home.appendingPathComponent("Library/Application Support/ShortcutCycle", isDirectory: true)
        makeDirectory(backupDir)
        let outside = makeTempDirectory(name: "outside")
        let outsideFile = outside.appendingPathComponent("backup.json")
        makeFile(outsideFile, contents: "{}")

        let result = URLCommandFileValidation.resolveBackupURL(
            target: .path(outsideFile.path),
            backupDirectory: backupDir,
            home: home
        )
        XCTAssertFailure(result, expected: .pathOutsideContainer)
    }

    func testResolveBackupURLByPathAcceptsInsideContainer() {
        let home = makeTempDirectory(name: "home")
        let backupDir = home.appendingPathComponent("Library/Application Support/ShortcutCycle", isDirectory: true)
        makeDirectory(backupDir)
        let insideFile = home.appendingPathComponent("tmp/backup.json")
        makeFile(insideFile, contents: "{}")

        let result = URLCommandFileValidation.resolveBackupURL(
            target: .path(insideFile.path),
            backupDirectory: backupDir,
            home: home
        )
        guard case .success(let url) = result else {
            return XCTFail("Expected success for backup path inside container")
        }
        XCTAssertEqual(canonicalPath(url), canonicalPath(insideFile))
    }

    func testResolveBackupURLByIndexAndLatestUseNewestFirst() {
        let home = makeTempDirectory(name: "home")
        let backupDir = home.appendingPathComponent("Library/Application Support/ShortcutCycle", isDirectory: true)
        makeDirectory(backupDir)

        let older = backupDir.appendingPathComponent("backup 2026-03-01 00-00-00.json")
        let newer = backupDir.appendingPathComponent("backup 2026-03-02 00-00-00.json")
        makeFile(older, contents: "{\"version\":1}")
        makeFile(newer, contents: "{\"version\":2}")

        try? FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: older.path)
        try? FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 2000)], ofItemAtPath: newer.path)

        let latest = URLCommandFileValidation.resolveBackupURL(
            target: nil,
            backupDirectory: backupDir,
            home: home
        )
        guard case .success(let latestURL) = latest else {
            return XCTFail("Expected latest backup to resolve")
        }
        XCTAssertEqual(canonicalPath(latestURL), canonicalPath(newer))

        let indexOne = URLCommandFileValidation.resolveBackupURL(
            target: .index(1),
            backupDirectory: backupDir,
            home: home
        )
        guard case .success(let indexOneURL) = indexOne else {
            return XCTFail("Expected backup index 1 to resolve")
        }
        XCTAssertEqual(canonicalPath(indexOneURL), canonicalPath(newer))

        let indexTwo = URLCommandFileValidation.resolveBackupURL(
            target: .index(2),
            backupDirectory: backupDir,
            home: home
        )
        guard case .success(let indexTwoURL) = indexTwo else {
            return XCTFail("Expected backup index 2 to resolve")
        }
        XCTAssertEqual(canonicalPath(indexTwoURL), canonicalPath(older))
    }

    func testResolveBackupURLReturnsNoBackupsAvailableWhenEmpty() {
        let home = makeTempDirectory(name: "home")
        let backupDir = home.appendingPathComponent("Library/Application Support/ShortcutCycle", isDirectory: true)
        makeDirectory(backupDir)

        let result = URLCommandFileValidation.resolveBackupURL(
            target: nil,
            backupDirectory: backupDir,
            home: home
        )
        XCTAssertFailure(result, expected: .noBackupsAvailable)
    }

    func testResolveBackupURLByIndexReturnsOutOfRangeError() {
        let home = makeTempDirectory(name: "home")
        let backupDir = home.appendingPathComponent("Library/Application Support/ShortcutCycle", isDirectory: true)
        makeDirectory(backupDir)

        let result = URLCommandFileValidation.resolveBackupURL(
            target: .index(1),
            backupDirectory: backupDir,
            home: home
        )
        XCTAssertFailure(result, expected: .backupIndexOutOfRange)
    }

    func testResolveBackupURLReturnsNoBackupsWhenBackupDirectoryUnreadable() {
        let home = makeTempDirectory(name: "home")
        let notADirectory = home.appendingPathComponent("backup-file.json", isDirectory: false)
        makeFile(notADirectory, contents: "{}")

        let result = URLCommandFileValidation.resolveBackupURL(
            target: nil,
            backupDirectory: notADirectory,
            home: home
        )
        XCTAssertFailure(result, expected: .noBackupsAvailable)
    }

    // MARK: - Helpers

    private func makeTempDirectory(name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        makeDirectory(url)
        temporaryURLs.append(url)
        return url
    }

    private func makeDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func makeFile(_ url: URL, contents: String) {
        makeDirectory(url.deletingLastPathComponent())
        try? Data(contents.utf8).write(to: url, options: .atomic)
    }

    private func XCTAssertFailure(
        _ result: Result<URL, URLCommandFileValidation.ValidationError>,
        expected: URLCommandFileValidation.ValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let error) = result else {
            return XCTFail("Expected failure with \(expected)", file: file, line: line)
        }
        XCTAssertEqual(error, expected, file: file, line: line)
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

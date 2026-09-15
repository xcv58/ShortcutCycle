import Foundation
import XCTest
@testable import ShortcutCycle

final class ScreenshotIsolationTests: XCTestCase {
    func testFixtureBackupsUseUniqueTemporaryRootsInsteadOfUserApplicationSupport() throws {
        let first = ScreenshotFileManager()
        let second = ScreenshotFileManager()
        let firstRoot = try XCTUnwrap(first.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let secondRoot = try XCTUnwrap(second.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let userRoot = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)

        XCTAssertNotEqual(firstRoot, secondRoot)
        XCTAssertNotEqual(firstRoot, userRoot)
        XCTAssertEqual(firstRoot.deletingLastPathComponent().standardizedFileURL,
                       FileManager.default.temporaryDirectory.standardizedFileURL)
        XCTAssertEqual(first.urls(for: .documentDirectory, in: .userDomainMask),
                       FileManager.default.urls(for: .documentDirectory, in: .userDomainMask))
    }
}

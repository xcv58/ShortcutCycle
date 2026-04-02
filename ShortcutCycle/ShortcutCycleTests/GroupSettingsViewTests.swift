import XCTest
@testable import ShortcutCycle

@MainActor
final class GroupSettingsViewTests: XCTestCase {
    func testGroupSettingsViewCanBeConstructedWithoutWelcomeRequestID() {
        _ = GroupSettingsView()
    }
}

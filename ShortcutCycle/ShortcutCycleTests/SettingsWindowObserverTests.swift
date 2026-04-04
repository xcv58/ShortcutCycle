import AppKit
import XCTest
@testable import ShortcutCycle

@MainActor
final class SettingsWindowObserverTests: XCTestCase {
    func testObserveSetsSettingsWindowIdentifier() {
        let coordinator = SettingsWindowObserver.Coordinator()
        let window = NSWindow()

        coordinator.observe(window: window)

        XCTAssertEqual(window.identifier?.rawValue, "settings")
    }

    func testObserveIsIdempotentForSameWindow() {
        let coordinator = SettingsWindowObserver.Coordinator()
        let window = NSWindow()

        coordinator.observe(window: window)
        coordinator.observe(window: window)

        XCTAssertEqual(window.identifier?.rawValue, "settings")
    }
}

import AppKit
import XCTest
@testable import ShortcutCycle

@MainActor
final class SettingsWindowObserverTests: XCTestCase {
    func testObserveInvokesCloseCallbackWhenWindowCloses() {
        let callbackFired = expectation(description: "window close callback")
        let coordinator = SettingsWindowObserver.Coordinator {
            callbackFired.fulfill()
        }
        let window = NSWindow()

        coordinator.observe(window: window)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        wait(for: [callbackFired], timeout: 1.0)
    }
}

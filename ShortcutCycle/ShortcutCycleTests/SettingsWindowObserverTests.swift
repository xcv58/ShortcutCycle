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

    func testShouldRevealFocusForTabKeyInObservedWindow() throws {
        let coordinator = SettingsWindowObserver.Coordinator()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        coordinator.observe(window: window)

        let tabEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\t",
                charactersIgnoringModifiers: "\t",
                isARepeat: false,
                keyCode: 48
            )
        )
        let letterEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            )
        )

        XCTAssertTrue(coordinator.shouldRevealFocus(for: tabEvent, in: window))
        XCTAssertFalse(coordinator.shouldRevealFocus(for: letterEvent, in: window))
    }

    func testRevealFocusedControlScrollsFirstResponderIntoView() {
        let coordinator = SettingsWindowObserver.Coordinator()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 900))
        let targetView = RecordingScrollableView(frame: NSRect(x: 20, y: 760, width: 120, height: 28))

        documentView.addSubview(targetView)
        scrollView.documentView = documentView
        window.contentView = scrollView

        coordinator.observe(window: window)

        XCTAssertTrue(window.makeFirstResponder(targetView))

        coordinator.revealFocusedControl()

        XCTAssertEqual(targetView.scrolledRect, targetView.bounds.insetBy(dx: 0, dy: -20))
    }

    func testShortcutGlyphLayoutSplitsModifierSequenceIntoIndividualSymbols() {
        XCTAssertEqual(KeyboardShortcutGlyphLayout.symbols(in: "⌥⌘↑"), ["⌥", "⌘", "↑"])
        XCTAssertEqual(KeyboardShortcutGlyphLayout.symbols(in: "⌘,"), ["⌘", ","])
    }
}

@MainActor
private final class RecordingScrollableView: NSView {
    var scrolledRect: NSRect?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func scrollToVisible(_ rect: NSRect) -> Bool {
        scrolledRect = rect
        return true
    }
}

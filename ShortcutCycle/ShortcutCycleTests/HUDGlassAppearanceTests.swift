import AppKit
import SwiftUI
import XCTest
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif
@testable import ShortcutCycle

@MainActor
final class HUDGlassAppearanceTests: XCTestCase {
    private var windows: [HUDWindow] = []
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HUDGlassAppearanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testGlassKeepsForegroundControlHittableAndDoesNotChangeLayout() {
        for scheme in [ColorScheme.light, .dark] {
            let button = NSButton(title: "Select app", target: nil, action: nil)
            let view = ButtonHost(button: button)
                .frame(width: 120, height: 40)
                .padding(24)
                .modifier(HUDGlassBackground(shape: RoundedRectangle(cornerRadius: 28)) {
                    RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial)
                })
                .environment(\.colorScheme, scheme)
            let hostingView = host(AnyView(view))

            XCTAssertEqual(hostingView.fittingSize.width, 168, accuracy: 1)
            XCTAssertEqual(hostingView.fittingSize.height, 88, accuracy: 1)
            let center = button.convert(
                NSPoint(x: button.bounds.midX, y: button.bounds.midY),
                to: hostingView
            )
            let hit = hostingView.hitTest(center)
            XCTAssertTrue(
                hit === button || hit?.isDescendant(of: button) == true,
                "The glass background must not intercept foreground control clicks."
            )
        }
    }

    func testHUDReusesPanelAcrossSelectionAndLayoutChanges() {
        let items = (0..<8).map {
            HUDAppItem(
                bundleId: "test.app.\($0)",
                name: "Application \($0)",
                icon: NSImage(size: NSSize(width: 72, height: 72))
            )
        }

        for theme in [AppTheme.light, .dark, .system] {
            defaults.set(theme.rawValue, forKey: "appTheme")
            let hostingView = host(hud(items: Array(items.prefix(3)), selected: items[0].id))
            let rowSize = hostingView.fittingSize
            let minimumRowWidth: CGFloat = 400 // Three icons, gaps, and horizontal padding.
            let minimumRowHeight: CGFloat = 200 // Icon height and vertical padding, before the label.
            XCTAssertGreaterThanOrEqual(rowSize.width, minimumRowWidth)
            XCTAssertGreaterThan(rowSize.height, minimumRowHeight)

            hostingView.rootView = hud(items: Array(items.prefix(3)), selected: items[2].id)
            hostingView.layoutSubtreeIfNeeded()
            XCTAssertEqual(hostingView.fittingSize.width, rowSize.width, accuracy: 1)
            XCTAssertEqual(hostingView.fittingSize.height, rowSize.height, accuracy: 1)

            hostingView.rootView = hud(items: items, selected: items[7].id)
            hostingView.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hostingView.fittingSize.width, rowSize.width)
            XCTAssertGreaterThan(hostingView.fittingSize.height, rowSize.height)

            hostingView.rootView = hud(items: Array(items.prefix(3)), selected: items[0].id)
            hostingView.layoutSubtreeIfNeeded()
            XCTAssertEqual(hostingView.fittingSize.width, rowSize.width, accuracy: 1)
            XCTAssertEqual(hostingView.fittingSize.height, rowSize.height, accuracy: 1)
        }
    }

    func testPreviewKeepsShortcutLayoutInStandardAndHighContrastAppearances() {
        // The preview must obey its explicit toggle, even when the live HUD's
        // persisted shortcut preference is disabled.
        defaults.set(false, forKey: "showShortcutInHUD")
        for appearance in [NSAppearance.Name.aqua, .darkAqua,
                           .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            let withoutShortcut = host(
                AnyView(HUDPreviewView(showShortcut: false).defaultAppStorage(defaults)),
                appearance: appearance
            ).fittingSize
            let withShortcut = host(
                AnyView(HUDPreviewView(showShortcut: true).defaultAppStorage(defaults)),
                appearance: appearance
            ).fittingSize

            XCTAssertGreaterThan(withoutShortcut.width, 0)
            XCTAssertEqual(withShortcut.width, withoutShortcut.width, accuracy: 1)
            XCTAssertGreaterThan(withShortcut.height, withoutShortcut.height)
            XCTAssertLessThanOrEqual(withShortcut.height, 160, "The preview must fit its settings canvas.")
            XCTAssertLessThanOrEqual(withShortcut.width, 320, "The preview must fit a narrow settings column.")
        }
    }

    private func hud(items: [HUDAppItem], selected: String) -> AnyView {
        AnyView(
            AppSwitcherHUDView(apps: items, activeAppId: selected, shortcutString: "⌘ + 1")
                .defaultAppStorage(defaults)
        )
    }

    private func host(
        _ rootView: AnyView,
        appearance: NSAppearance.Name = .aqua
    ) -> NSHostingView<AnyView> {
        let hostingView = NSHostingView(rootView: rootView)
        let window = HUDWindow()
        window.appearance = NSAppearance(named: appearance)
        window.ignoresMouseEvents = false
        window.contentView = hostingView
        window.setContentSize(hostingView.fittingSize)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        windows.append(window)
        return hostingView
    }

    private struct ButtonHost: NSViewRepresentable {
        let button: NSButton

        func makeNSView(context: Context) -> NSButton { button }
        func updateNSView(_ nsView: NSButton, context: Context) {}
    }
}

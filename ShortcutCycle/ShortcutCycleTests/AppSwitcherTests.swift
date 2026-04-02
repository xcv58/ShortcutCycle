import XCTest

#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#endif
@testable import ShortcutCycle

@MainActor
final class AppSwitcherTests: XCTestCase {
    private var switcher: AppSwitcher!
    private var originalShowHUDValue: Any?

    override func setUp() async throws {
        switcher = AppSwitcher.shared
        originalShowHUDValue = UserDefaults.standard.object(forKey: "showHUD")
        NSApp?.unhide(nil)
    }

    override func tearDown() async throws {
        if let originalShowHUDValue {
            UserDefaults.standard.set(originalShowHUDValue, forKey: "showHUD")
        } else {
            UserDefaults.standard.removeObject(forKey: "showHUD")
        }

        switcher.isSwitcherAppActive = {
            NSApp?.isActive == true
        }
        switcher.unhideRunningApp = { app in
            app.unhide()
        }
        switcher.activateRunningAppInstance = { app in
            app.activate(options: .activateAllWindows)
        }
        NSApp?.unhide(nil)
    }

    func testAppSwitchDoesNotHideTheMenuBarApp() throws {
        guard let app = NSApp else {
            throw XCTSkip("Requires a hosted NSApplication to verify hidden-state behavior")
        }

        app.unhide(nil)

        let targetApp = try XCTUnwrap(
            NSWorkspace.shared.frontmostApplication?.activationPolicy == .regular
                ? NSWorkspace.shared.frontmostApplication
                : NSWorkspace.shared.runningApplications.first(where: {
                    $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                })
        )
        let bundleId = try XCTUnwrap(targetApp.bundleIdentifier)

        let suiteName = "AppSwitcherTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = GroupStore(userDefaults: defaults, backupDebounceInterval: 3600)
        let group = AppGroup(
            name: "Switch Test",
            apps: [AppItem(bundleIdentifier: bundleId, name: targetApp.localizedName ?? bundleId)]
        )
        store.groups = [group]

        UserDefaults.standard.set(false, forKey: "showHUD")

        switcher.isSwitcherAppActive = { true }
        switcher.unhideRunningApp = { _ in }
        switcher.activateRunningAppInstance = { _ in true }

        switcher.handleShortcut(for: group, store: store)

        XCTAssertEqual(app.isHidden, false, "Switching apps should not hide the menu bar app itself")
    }
}

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

        // Restore default closures on the shared singleton so in-flight
        // DispatchQueue.main.asyncAfter blocks in activateRunningApp (fired 0.1s
        // after handleShortcut) call the real APIs rather than test stubs.
        switcher.unhideRunningApp = { app in
            app.unhide()
        }
        switcher.activateRunningAppInstance = { app in
            if NSApp?.isActive == true {
                NSApp?.yieldActivation(to: app)
                return app.activate(from: .current, options: .activateAllWindows)
            }
            return app.activate(options: .activateAllWindows)
        }
        switcher.isRunningAppActive = { app in
            app.isActive
        }
        switcher.hideRunningApp = { app in
            app.hide()
        }
        HUDManager.shared.hide()
        NSApp?.unhide(nil)
    }

    private func singleRegularRunningApp() throws -> NSRunningApplication {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { candidate in
            guard candidate.activationPolicy == .regular,
                  let bundleId = candidate.bundleIdentifier else {
                return false
            }
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .filter { $0.activationPolicy == .regular }
                .count == 1
        }) else {
            throw XCTSkip("Requires a bundle with exactly one regular-policy running app")
        }
        return app
    }

    private func makeStoreAndGroup(for app: NSRunningApplication) throws -> (GroupStore, AppGroup) {
        let bundleId = try XCTUnwrap(app.bundleIdentifier)
        let suiteName = "AppSwitcherSingleAppTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = GroupStore(userDefaults: defaults, backupDebounceInterval: 3600)
        let group = AppGroup(
            name: "Single Running App",
            apps: [AppItem(bundleIdentifier: bundleId, name: app.localizedName ?? bundleId)],
            openAppIfNeeded: false
        )
        store.groups = [group]
        return (store, group)
    }

    func testAppSwitchDoesNotHideTheMenuBarApp() throws {
        guard let app = NSApp else {
            throw XCTSkip("Requires a hosted NSApplication to verify hidden-state behavior")
        }

        app.unhide(nil)

        guard let targetApp = NSWorkspace.shared.frontmostApplication?.activationPolicy == .regular
            ? NSWorkspace.shared.frontmostApplication
            : NSWorkspace.shared.runningApplications.first(where: {
                $0.activationPolicy == .regular && $0.bundleIdentifier != nil
            })
        else {
            throw XCTSkip("Requires at least one regular-policy app to be running")
        }
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

        switcher.unhideRunningApp = { _ in }
        switcher.activateRunningAppInstance = { _ in true }

        switcher.handleShortcut(for: group, store: store)

        XCTAssertEqual(app.isHidden, false, "Switching apps should not hide the menu bar app itself")
    }

    func testFrontmostSingleRunningAppQuickReleaseDefersThenHides() throws {
        let app = try singleRegularRunningApp()
        let (store, group) = try makeStoreAndGroup(for: app)
        let manager = HUDManager.shared
        let savedPresentHUDWindow = manager.presentHUDWindow
        let savedActivatePendingTargetApp = manager.activatePendingTargetApp
        defer {
            manager.hide()
            manager.presentHUDWindow = savedPresentHUDWindow
            manager.activatePendingTargetApp = savedActivatePendingTargetApp
        }

        var hideCount = 0
        var activationCount = 0
        switcher.isRunningAppActive = { _ in true }
        switcher.hideRunningApp = { _ in hideCount += 1 }
        manager.presentHUDWindow = { _ in }
        manager.activatePendingTargetApp = { _ in activationCount += 1 }
        UserDefaults.standard.set(true, forKey: "showHUD")

        switcher.handleShortcut(for: group, store: store)

        XCTAssertEqual(hideCount, 0, "Key-down should not hide the frontmost app before tap-versus-hold intent is known")
        XCTAssertTrue(manager.isSessionActive, "The shortcut should begin a pending HUD session")

        manager.finalizeSwitchForTesting()

        XCTAssertEqual(hideCount, 1, "A quick release should preserve the single-app toggle behavior")
        XCTAssertEqual(activationCount, 0, "Quick release must not immediately reactivate the app it toggled away")
        XCTAssertFalse(manager.isSessionActive)
    }

    func testFrontmostSingleRunningAppWithoutHUDHidesImmediately() throws {
        let app = try singleRegularRunningApp()
        let (store, group) = try makeStoreAndGroup(for: app)
        var hideCount = 0

        switcher.isRunningAppActive = { _ in true }
        switcher.hideRunningApp = { _ in hideCount += 1 }
        switcher.activateRunningAppInstance = { _ in
            XCTFail("A frontmost single app should toggle away instead of being reactivated")
            return true
        }
        UserDefaults.standard.set(false, forKey: "showHUD")

        switcher.handleShortcut(for: group, store: store)

        XCTAssertEqual(hideCount, 1, "HUD-disabled shortcuts should retain immediate single-app toggling")
        XCTAssertFalse(HUDManager.shared.isSessionActive)
    }
}

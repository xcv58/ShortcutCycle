import XCTest
import AppKit
import SwiftUI
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#endif
@testable import ShortcutCycle

@MainActor
final class GroupEditViewTests: XCTestCase {

    private final class RunningCandidatesProviderSpy {
        private(set) var calls: [[AppItem]] = []

        func provider(_ apps: [AppItem]) -> [AppItem] {
            calls.append(apps)
            return []
        }
    }

    private final class ReorderState {
        var draggingApp: AppItem?
        var dragPreviewApps: [AppItem]?
    }

    private var userDefaults: UserDefaults!
    private var store: GroupStore!
    private var window: NSWindow?
    private var suiteName: String!

    override func setUp() {
        super.setUp()

        suiteName = "GroupEditViewTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        store = GroupStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        window?.orderOut(nil)
        window = nil

        if let suiteName {
            userDefaults?.removePersistentDomain(forName: suiteName)
        }

        store = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCyclingModeUsesSegmentedControlWhenEditorIsWide() throws {
        let hostingView = hostGroupEditView(width: 720)

        XCTAssertNotNil(
            findSubview(ofType: NSSegmentedControl.self, in: hostingView),
            "Wide layouts should keep the Cycling Mode control segmented."
        )
    }

    func testCyclingModeFallsBackFromSegmentedControlWhenEditorIsNarrow() throws {
        let hostingView = hostGroupEditView(width: 320)

        XCTAssertNil(
            findSubview(ofType: NSSegmentedControl.self, in: hostingView),
            "Narrow layouts should avoid rendering the Cycling Mode control as a segmented control."
        )
        XCTAssertNotNil(
            findSubview(ofType: NSPopUpButton.self, in: hostingView),
            "Narrow layouts should still render a usable Cycling Mode picker."
        )
    }

    func testRunningAppsQuickAddSectionVisibilityDependsOnCandidates() {
        XCTAssertTrue(
            GroupEditView.shouldShowRunningAppQuickAddSection([AppItem(bundleIdentifier: "com.test.mail", name: "Mail")])
        )
        XCTAssertFalse(GroupEditView.shouldShowRunningAppQuickAddSection([]))
    }

    func testAccessibilityReorderDestinationsRespectBoundaries() {
        XCTAssertNil(
            AppAccessibilityReorder.destination(for: 0, direction: .earlier, count: 3)
        )
        XCTAssertEqual(
            AppAccessibilityReorder.destination(for: 1, direction: .earlier, count: 3),
            0
        )
        XCTAssertEqual(
            AppAccessibilityReorder.destination(for: 1, direction: .later, count: 3),
            3
        )
        XCTAssertNil(
            AppAccessibilityReorder.destination(for: 2, direction: .later, count: 3)
        )
        XCTAssertNil(
            AppAccessibilityReorder.destination(for: -1, direction: .earlier, count: 3)
        )
        XCTAssertNil(
            AppAccessibilityReorder.destination(for: 3, direction: .later, count: 3)
        )
    }

    func testHUDMotionPolicyDisablesSelectionMotionWhenRequested() {
        XCTAssertFalse(HUDMotionPolicy.shouldAnimateSelection(reduceMotion: true))
        XCTAssertTrue(HUDMotionPolicy.shouldAnimateSelection(reduceMotion: false))
        XCTAssertEqual(
            HUDMotionPolicy.iconScale(isActive: true, isHovering: true, reduceMotion: true),
            1.0
        )
        XCTAssertEqual(
            HUDMotionPolicy.iconScale(isActive: true, isHovering: false, reduceMotion: false),
            1.15
        )
        XCTAssertEqual(
            HUDMotionPolicy.iconScale(isActive: false, isHovering: true, reduceMotion: false),
            1.08
        )
        XCTAssertEqual(
            HUDMotionPolicy.iconScale(isActive: false, isHovering: false, reduceMotion: false),
            1.0
        )
    }

    func testRunningAppCandidatesDoNotRefreshForPureReorder() throws {
        let groupId = try XCTUnwrap(store.groups.first?.id)
        let app1 = AppItem(bundleIdentifier: "com.test.alpha", name: "Alpha")
        let app2 = AppItem(bundleIdentifier: "com.test.beta", name: "Beta")
        let app3 = AppItem(bundleIdentifier: "com.test.gamma", name: "Gamma")
        let providerSpy = RunningCandidatesProviderSpy()

        store.addApp(app1, to: groupId)
        store.addApp(app2, to: groupId)

        _ = hostGroupEditView(width: 720, runningAppCandidatesProvider: providerSpy.provider)
        XCTAssertTrue(
            drainMainRunLoop(timeout: 2.0, until: { !providerSpy.calls.isEmpty }),
            "Hosting the editor should load initial running-app candidates"
        )
        let initialCallCount = providerSpy.calls.count

        store.replaceApps(in: groupId, with: [app2, app1])
        drainMainRunLoop()
        XCTAssertEqual(providerSpy.calls.count, initialCallCount)

        store.addApp(app3, to: groupId)
        XCTAssertTrue(
            drainMainRunLoop(timeout: 2.0, until: { providerSpy.calls.count >= initialCallCount + 1 }),
            "Adding an app should refresh running-app candidates"
        )
        XCTAssertEqual(providerSpy.calls.count, initialCallCount + 1)
        XCTAssertEqual(providerSpy.calls.last?.map(\.bundleIdentifier), [app2, app1, app3].map(\.bundleIdentifier))
    }

    func testAppReorderDelegateBuildsPreviewFromStoreApps() throws {
        let groupId = try XCTUnwrap(store.groups.first?.id)
        let app1 = AppItem(bundleIdentifier: "com.test.alpha", name: "Alpha")
        let app2 = AppItem(bundleIdentifier: "com.test.beta", name: "Beta")
        let app3 = AppItem(bundleIdentifier: "com.test.gamma", name: "Gamma")

        store.addApp(app1, to: groupId)
        store.addApp(app2, to: groupId)
        store.addApp(app3, to: groupId)

        let reorderState = ReorderState()
        reorderState.draggingApp = app1
        let delegate = makeReorderDelegate(
            item: app3,
            reorderState: reorderState,
            groupId: groupId
        )

        delegate.updatePreviewOrder()

        XCTAssertEqual(reorderState.dragPreviewApps, [app2, app3, app1])
    }

    func testAppReorderDelegateUsesExistingPreviewForSubsequentHover() throws {
        let groupId = try XCTUnwrap(store.groups.first?.id)
        let app1 = AppItem(bundleIdentifier: "com.test.alpha", name: "Alpha")
        let app2 = AppItem(bundleIdentifier: "com.test.beta", name: "Beta")
        let app3 = AppItem(bundleIdentifier: "com.test.gamma", name: "Gamma")

        store.addApp(app1, to: groupId)
        store.addApp(app2, to: groupId)
        store.addApp(app3, to: groupId)

        let reorderState = ReorderState()
        reorderState.draggingApp = app1
        reorderState.dragPreviewApps = [app2, app3, app1]
        let delegate = makeReorderDelegate(
            item: app2,
            reorderState: reorderState,
            groupId: groupId
        )

        delegate.updatePreviewOrder()

        XCTAssertEqual(reorderState.dragPreviewApps, [app1, app2, app3])
    }

    func testAppReorderDelegateCommitPersistsPreviewAndClearsDragState() throws {
        let groupId = try XCTUnwrap(store.groups.first?.id)
        let app1 = AppItem(bundleIdentifier: "com.test.alpha", name: "Alpha")
        let app2 = AppItem(bundleIdentifier: "com.test.beta", name: "Beta")

        store.addApp(app1, to: groupId)
        store.addApp(app2, to: groupId)

        let reorderState = ReorderState()
        reorderState.draggingApp = app1
        reorderState.dragPreviewApps = [app2, app1]
        let delegate = makeReorderDelegate(
            item: app2,
            reorderState: reorderState,
            groupId: groupId
        )

        delegate.commitPreviewOrder()

        let updatedApps = try XCTUnwrap(store.groups.first(where: { $0.id == groupId })?.apps)
        XCTAssertEqual(updatedApps, [app2, app1])
        XCTAssertNil(reorderState.draggingApp)
        XCTAssertNil(reorderState.dragPreviewApps)
    }

    func testAppGridItemRendersRegularAndPlaceholderStates() {
        let app = AppItem(bundleIdentifier: "com.test.grid", name: "Grid App")

        let hostingView = hostView(
            AnyView(
                VStack {
                    AppGridItemView(app: app, isPlaceholder: false, onDelete: {})
                    AppGridItemView(app: app, isPlaceholder: true, onDelete: {})
                }
                .frame(width: 220, height: 260)
            ),
            width: 220,
            height: 260
        )

        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
    }

    private func hostGroupEditView(
        width: CGFloat,
        height: CGFloat = 600,
        runningAppCandidatesProvider: (([AppItem]) -> [AppItem])? = nil
    ) -> NSHostingView<AnyView> {
        let groupId = try! XCTUnwrap(store.groups.first?.id)
        let rootView: AnyView

        if let runningAppCandidatesProvider {
            rootView = AnyView(
                GroupEditView(groupId: groupId, runningAppCandidatesProvider: runningAppCandidatesProvider)
                    .environmentObject(store)
                    .frame(width: width, height: height)
            )
        } else {
            rootView = AnyView(
                GroupEditView(groupId: groupId)
                    .environmentObject(store)
                    .frame(width: width, height: height)
            )
        }

        return hostView(rootView, width: width, height: height)
    }

    private func hostView(
        _ rootView: AnyView,
        width: CGFloat,
        height: CGFloat
    ) -> NSHostingView<AnyView> {
        let hostingView = NSHostingView(rootView: rootView)
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window?.contentView = hostingView
        window?.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        drainMainRunLoop()
        return hostingView
    }

    @discardableResult
    private func drainMainRunLoop(
        timeout: TimeInterval = 0.1,
        until condition: (() -> Bool)? = nil
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if condition?() == true {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline

        return condition?() ?? true
    }

    private func makeReorderDelegate(
        item: AppItem,
        reorderState: ReorderState,
        groupId: UUID
    ) -> AppReorderDelegate {
        AppReorderDelegate(
            item: item,
            draggingApp: Binding(
                get: { reorderState.draggingApp },
                set: { reorderState.draggingApp = $0 }
            ),
            dragPreviewApps: Binding(
                get: { reorderState.dragPreviewApps },
                set: { reorderState.dragPreviewApps = $0 }
            ),
            store: store,
            groupId: groupId
        )
    }

    private func findSubview<ViewType: NSView>(ofType type: ViewType.Type, in root: NSView) -> ViewType? {
        if let match = root as? ViewType {
            return match
        }

        for subview in root.subviews {
            if let match = findSubview(ofType: type, in: subview) {
                return match
            }
        }

        return nil
    }
}

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

    func testAppPickerPresentsAsSheetForVisibleSettingsWindow() {
        let settingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: true,
            isOnActiveSpace: true
        )

        switch AppPickerPanelPresentation.destination(in: [settingsWindow]) {
        case .sheet(let owner):
            XCTAssertTrue(owner === settingsWindow)
        case .standalone:
            XCTFail("A visible Settings window should own the app picker sheet.")
        }
    }

    func testAppPickerUsesStandalonePanelWithoutVisibleSettingsWindow() {
        let hiddenSettingsWindow = MockWindow(
            identifier: NSUserInterfaceItemIdentifier("settings"),
            isVisible: false,
            isOnActiveSpace: true
        )

        switch AppPickerPanelPresentation.destination(in: [hiddenSettingsWindow]) {
        case .sheet:
            XCTFail("A hidden Settings window cannot own the app picker sheet.")
        case .standalone:
            break
        }
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

    func testHUDAppKitHoverViewEmitsOnlyHoverTransitions() {
        let hoverView = HUDAppKitHoverView()
        var transitions: [Bool] = []
        hoverView.onHoverChange = { transitions.append($0) }

        hoverView.updateHovering(true)
        hoverView.updateHovering(true)
        hoverView.updateHovering(false)
        hoverView.updateHovering(false)

        XCTAssertEqual(transitions, [true, false])
        XCTAssertFalse(hoverView.isHovering)
    }

    func testHUDAppKitHoverViewReplacesItsTrackingAreaWithoutAccumulating() throws {
        let hoverView = HUDAppKitHoverView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))

        hoverView.updateTrackingAreas()
        let firstTrackingArea = try XCTUnwrap(hoverView.managedTrackingArea)
        XCTAssertTrue(hoverView.trackingAreas.contains { $0 === firstTrackingArea })

        hoverView.updateTrackingAreas()
        let secondTrackingArea = try XCTUnwrap(hoverView.managedTrackingArea)

        XCTAssertFalse(firstTrackingArea === secondTrackingArea)
        XCTAssertFalse(hoverView.trackingAreas.contains { $0 === firstTrackingArea })
        XCTAssertTrue(hoverView.trackingAreas.contains { $0 === secondTrackingArea })
        XCTAssertEqual(
            hoverView.trackingAreas.filter { $0.owner as? HUDAppKitHoverView === hoverView }.count,
            1
        )
    }

    func testHUDAppKitHoverViewCleanupResetsStateAndDetachesCallback() {
        let hoverView = HUDAppKitHoverView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
        var transitions: [Bool] = []
        hoverView.onHoverChange = { transitions.append($0) }
        hoverView.updateTrackingAreas()
        hoverView.updateHovering(true)

        hoverView.stopTracking()

        XCTAssertEqual(transitions, [true])
        XCTAssertFalse(hoverView.isHovering)
        XCTAssertNil(hoverView.managedTrackingArea)
        XCTAssertNil(hoverView.onHoverChange)
    }

    func testHUDAppKitHoverBridgeUpdatesRenderedHoverAppearance() throws {
        let icon = NSImage(size: NSSize(width: 64, height: 64))
        icon.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
        icon.unlockFocus()

        let app = HUDAppItem(id: "com.test.hover", name: "Hover", icon: icon, isRunning: true)
        let hostingView = hostView(
            AnyView(
                HUDAppButton(app: app, icon: icon, isActive: false, onSelect: nil)
                    .frame(width: 96, height: 96)
            ),
            width: 96,
            height: 96
        )
        let hoverView = try XCTUnwrap(findSubview(ofType: HUDAppKitHoverView.self, in: hostingView))
        let restingSnapshot = try XCTUnwrap(snapshotData(of: hostingView))

        hoverView.updateHovering(true)
        drainMainRunLoop(timeout: 0.3)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let hoveredSnapshot = try XCTUnwrap(snapshotData(of: hostingView))
        XCTAssertNotEqual(restingSnapshot, hoveredSnapshot)
        XCTAssertTrue(hoverView.isHovering)
    }

    func testHorizontalHUDCentersSmallAppGroupsWithoutScrollView() throws {
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        let apps = [
            HUDAppItem(id: "com.test.calendar", name: "Calendar", icon: icon, isRunning: true),
            HUDAppItem(id: "com.test.mail", name: "Mail", icon: icon, isRunning: true)
        ]
        let hostingView = hostFittingView(
            AnyView(
                AppSwitcherHUDView(
                    apps: apps,
                    activeAppId: apps[0].id,
                    shortcutString: "⌥ + 1"
                )
            )
        )
        let hoverViews = findSubviews(ofType: HUDAppKitHoverView.self, in: hostingView)
        let itemFrames = hoverViews.map { $0.convert($0.bounds, to: hostingView) }
        let leftMargin = try XCTUnwrap(itemFrames.map(\.minX).min())
        let rightMargin = hostingView.bounds.maxX - (try XCTUnwrap(itemFrames.map(\.maxX).max()))

        XCTAssertNil(findSubview(ofType: NSScrollView.self, in: hostingView))
        XCTAssertEqual(hoverViews.count, apps.count)
        XCTAssertEqual(leftMargin, rightMargin, accuracy: 1.0)
    }

    func testGridHUDKeepsScrollViewForLargerAppGroups() {
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        let apps = (0..<6).map { index in
            HUDAppItem(
                id: "com.test.grid.\(index)",
                name: "Grid \(index)",
                icon: icon,
                isRunning: true
            )
        }
        let hostingView = hostFittingView(
            AnyView(
                AppSwitcherHUDView(
                    apps: apps,
                    activeAppId: apps[0].id,
                    shortcutString: "⌥ + 1"
                )
            )
        )

        XCTAssertNotNil(findSubview(ofType: NSScrollView.self, in: hostingView))
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

    private func hostFittingView(_ rootView: AnyView) -> NSHostingView<AnyView> {
        let sizingView = NSHostingView(rootView: rootView)
        let fittingSize = sizingView.fittingSize
        return hostView(rootView, width: fittingSize.width, height: fittingSize.height)
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

    private func findSubviews<ViewType: NSView>(ofType type: ViewType.Type, in root: NSView) -> [ViewType] {
        var matches: [ViewType] = []
        if let match = root as? ViewType {
            matches.append(match)
        }
        for subview in root.subviews {
            matches.append(contentsOf: findSubviews(ofType: type, in: subview))
        }
        return matches
    }

    private func snapshotData(of view: NSView) -> Data? {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        return representation.representation(using: .png, properties: [:])
    }
}

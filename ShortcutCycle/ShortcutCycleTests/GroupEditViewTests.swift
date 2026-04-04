import XCTest
import AppKit
import SwiftUI
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#endif
@testable import ShortcutCycle

@MainActor
final class GroupEditViewTests: XCTestCase {

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

    private func hostGroupEditView(
        width: CGFloat,
        height: CGFloat = 600
    ) -> NSHostingView<AnyView> {
        let groupId = try! XCTUnwrap(store.groups.first?.id)
        let rootView = AnyView(
            GroupEditView(groupId: groupId)
                .environmentObject(store)
                .frame(width: width, height: height)
        )
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
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return hostingView
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

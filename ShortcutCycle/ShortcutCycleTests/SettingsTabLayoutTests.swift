import AppKit
import SwiftUI
import XCTest
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif
@testable import ShortcutCycle

@MainActor
final class SettingsTabLayoutTests: XCTestCase {
    func testChangingGroupsEndsNameEditingButAllowsDeliberateRefocus() async throws {
        let suite = "SettingsTabFocusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GroupStore(userDefaults: defaults)
        let first = try XCTUnwrap(store.groups.first)
        let second = try XCTUnwrap(store.groups.dropFirst().first)
        store.selectedGroupId = first.id
        let host = NSHostingController(rootView: MainView().environmentObject(store).environmentObject(LocaleObserver()))
        let window = NSWindow(contentViewController: host)
        window.setContentSize(NSSize(width: 1000, height: 600))
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
        }
        window.makeKeyAndOrderFront(nil)
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        func nameField(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.compactMap { nameField(in: $0) }.first
        }
        let field = try XCTUnwrap(nameField(in: host.view))
        XCTAssertNil(field.currentEditor(), "Opening settings must not start renaming a group.")
        XCTAssertTrue(window.makeFirstResponder(field))
        await settle()
        XCTAssertNotNil(field.currentEditor(), "Explicit focus must still allow editing.")

        store.selectedGroupId = second.id
        try await Task.sleep(for: .milliseconds(400))
        let nextField = try XCTUnwrap(nameField(in: host.view))
        XCTAssertEqual(nextField.stringValue, second.name)
        XCTAssertNil(nextField.currentEditor(), "Changing groups must end editing, even if the old name was focused.")
        XCTAssertEqual(store.groups.first(where: { $0.id == first.id })?.name, first.name)
        XCTAssertEqual(store.groups.first(where: { $0.id == second.id })?.name, second.name)

        XCTAssertTrue(window.makeFirstResponder(nextField))
        await settle()
        let editor = try XCTUnwrap(nextField.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("Renamed intentionally", replacementRange: editor.selectedRange())
        await settle()
        XCTAssertEqual(store.groups.first(where: { $0.id == second.id })?.name, "Renamed intentionally")

        NotificationCenter.default.post(name: .settingsTabRequested, object: URLSettingsTab.general.rawValue)
        try await Task.sleep(for: .milliseconds(100))
        NotificationCenter.default.post(name: .settingsTabRequested, object: URLSettingsTab.groups.rawValue)
        try await Task.sleep(for: .milliseconds(400))
        let returnedField = try XCTUnwrap(nameField(in: host.view))
        XCTAssertNil(returnedField.currentEditor(), "Returning from General must not resume a rename.")
        XCTAssertEqual(returnedField.stringValue, "Renamed intentionally")

        window.makeFirstResponder(nil)
        for _ in 0..<20 {
            window.selectNextKeyView(nil)
            await settle()
            if returnedField.currentEditor() != nil { break }
        }
        XCTAssertNotNil(returnedField.currentEditor(), "Keyboard traversal must still reach the name field.")
    }

    func testSidebarWidthSurvivesCollapseAndWindowResize() {
        let controller = SettingsGroupSplitController()
        controller.sidebarHost.rootView = AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity))
        controller.detailHost.rootView = AnyView(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity))
        controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        controller.splitView.setPosition(300, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.sidebarHost.view.frame.width, 300, accuracy: 1)

        controller.setSidebarCollapsed(true)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(controller.splitViewItems[0].isCollapsed)
        controller.setSidebarCollapsed(false)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.sidebarHost.view.frame.width, 300, accuracy: 1)

        controller.view.frame.size.width = 800
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.sidebarHost.view.frame.width, 300, accuracy: 1)
        XCTAssertEqual(controller.splitViewItems[0].behavior, .default)
    }

    func testNativeCollapsePublishesLatestStateWithoutProgrammaticEcho() async {
        let controller = SettingsGroupSplitController()
        var changes: [Bool] = []
        controller.onVisibilityChange = { changes.append($0) }
        controller.setSidebarCollapsed(true)
        await settle()
        XCTAssertTrue(changes.isEmpty)

        controller.toggleSidebar(nil)
        await settle()
        XCTAssertEqual(changes.last, false)

        controller.toggleSidebar(nil)
        controller.toggleSidebar(nil)
        await settle()
        XCTAssertFalse(controller.splitViewItems[0].isCollapsed)
        XCTAssertTrue(changes.allSatisfy { !$0 })
    }

    func testRealSidebarContentRemainsResizable() {
        let suite = "SettingsTabLayoutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GroupStore(userDefaults: defaults)
        let controller = SettingsGroupSplitController()
        controller.sidebarHost.rootView = AnyView(GroupListView(selection: .constant(store.selectedGroupId)).environmentObject(store))
        controller.detailHost.rootView = AnyView(GroupEditView(groupId: store.selectedGroupId!).environmentObject(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1000, height: 600))
        defer { window.contentViewController = nil }
        controller.view.layoutSubtreeIfNeeded()
        controller.viewDidLayout()
        controller.splitView.setPosition(320, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.sidebarHost.view.frame.width, 320, accuracy: 1)
    }

    func testSplitViewInsideSettingsWindowCanResize() async throws {
        let suite = "SettingsTabLayoutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GroupStore(userDefaults: defaults)
        let host = NSHostingController(rootView: MainView().environmentObject(store).environmentObject(LocaleObserver()))
        let window = NSWindow(contentViewController: host)
        window.setContentSize(NSSize(width: 1000, height: 600))
        defer { window.contentViewController = nil }
        host.view.layoutSubtreeIfNeeded()
        await settle()
        host.view.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> SettingsGroupSplitController? {
            if let split = view.nextResponder as? SettingsGroupSplitController { return split }
            return view.subviews.compactMap { find($0) }.first
        }
        let controller = try XCTUnwrap(find(host.view))
        controller.splitView.setPosition(320, ofDividerAt: 0)
        host.view.layoutSubtreeIfNeeded()
        await settle()
        host.view.layoutSubtreeIfNeeded()
        await settle()
        XCTAssertTrue(find(host.view) === controller)
        let dividerPoint = NSPoint(x: controller.splitView.arrangedSubviews[0].frame.maxX + 0.5, y: 200)
        let windowPoint = controller.splitView.convert(dividerPoint, to: host.view)
        XCTAssertTrue(host.view.hitTest(windowPoint) === controller.splitView)
        let grabPoint = controller.splitView.convert(NSPoint(x: dividerPoint.x - 3, y: 200), to: host.view)
        XCTAssertTrue(host.view.hitTest(grabPoint) === controller.splitView,
                      "The divider must be grabbable next to its thin visible line.")
        let contentPoint = controller.splitView.convert(NSPoint(x: 100, y: 200), to: host.view)
        XCTAssertFalse(host.view.hitTest(contentPoint) === controller.splitView,
                       "The divider must not intercept ordinary sidebar clicks.")
        XCTAssertEqual(controller.sidebarHost.view.frame.width, 320, accuracy: 1)
    }

    private func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

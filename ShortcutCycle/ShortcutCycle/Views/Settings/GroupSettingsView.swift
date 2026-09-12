import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

enum SettingsChromePalette {
    static func windowBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : .clear
    }

    static func sidebarBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(nsColor: .underPageBackgroundColor) : .clear
    }

    static func panelBackground(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.88 : 0.75)
    }

    static func panelBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .separatorColor).opacity(0.18)
            : Color.secondary.opacity(0.08)
    }

    static func inlineFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.76)
            : Color.secondary.opacity(0.10)
    }

    static func chipFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .quaternaryLabelColor).opacity(0.45)
            : Color.gray.opacity(0.20)
    }

    static func badgeFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .quaternaryLabelColor).opacity(0.40)
            : Color.gray.opacity(0.50)
    }

    static func neutralHoverFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.84)
            : Color.accentColor.opacity(0.10)
    }

    static func neutralHoverBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .separatorColor).opacity(0.24)
            : Color.accentColor.opacity(0.28)
    }

    static func dropZoneFill(for colorScheme: ColorScheme, targeted: Bool) -> Color {
        if targeted {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.10)
        }

        return colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.30)
            : .clear
    }

    static func dropZoneBorder(for colorScheme: ColorScheme, targeted: Bool) -> Color {
        if targeted {
            return colorScheme == .dark
                ? Color.accentColor.opacity(0.58)
                : .accentColor
        }

        return colorScheme == .dark
            ? Color(nsColor: .quaternaryLabelColor).opacity(0.72)
            : Color.gray.opacity(0.30)
    }

    static func focusRingFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.18)
            : Color.accentColor.opacity(0.10)
    }

    static func focusRingBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.95)
            : Color.accentColor.opacity(0.65)
    }

    static func focusRingGlow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.30)
            : Color.accentColor.opacity(0.16)
    }

    static func hoverRingFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.10)
            : inlineFill(for: colorScheme)
    }

    static func hoverRingBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.48)
            : neutralHoverBorder(for: colorScheme)
    }

    static func hoverRingGlow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.12)
            : .clear
    }
}

struct SettingsSectionDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        if colorScheme == .dark {
            Rectangle()
                .fill(SettingsChromePalette.panelBorder(for: colorScheme))
                .frame(height: 1)
        } else {
            Divider()
        }
    }
}

struct GroupSettingsView: View {
    @EnvironmentObject var store: GroupStore
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingSelectedGroupId: UUID?
    @State private var pendingSelectionRequestID: UUID?

    /// Keep the UI responsive by showing a temporary local selection immediately while
    /// still deferring the store write that previously avoided an AttributeGraph cycle.
    private var selectedGroupIdBinding: Binding<UUID?> {
        Binding(
            get: { pendingSelectedGroupId ?? store.selectedGroupId },
            set: { newValue in
                guard store.selectedGroupId != newValue else {
                    pendingSelectedGroupId = nil
                    pendingSelectionRequestID = nil
                    return
                }

                if let newValue {
                    GroupSwitchPerformanceTracker.shared.beginGroupSwitch(
                        to: newValue,
                        source: "sidebar",
                        expectedGroupIconCount: appCount(for: newValue)
                    )
                }

                let requestID = UUID()
                pendingSelectedGroupId = newValue
                pendingSelectionRequestID = requestID

                Task { @MainActor in
                    guard pendingSelectionRequestID == requestID else { return }

                    if store.selectedGroupId != newValue {
                        store.selectedGroupId = newValue
                    }

                    if pendingSelectionRequestID == requestID, pendingSelectedGroupId == newValue {
                        pendingSelectedGroupId = nil
                        pendingSelectionRequestID = nil
                    }
                }
            }
        )
    }

    private var visibleSelectedGroupId: UUID? {
        pendingSelectedGroupId ?? store.selectedGroupId
    }

    private func appCount(for groupId: UUID?) -> Int {
        guard let groupId else { return 0 }
        return store.groups.first(where: { $0.id == groupId })?.apps.count ?? 0
    }

    var body: some View {
        SettingsGroupSplitView(columnVisibility: $store.columnVisibility) {
            GroupListView(selection: selectedGroupIdBinding)
        } detail: {
            if let selectedId = visibleSelectedGroupId {
                GroupEditView(groupId: selectedId)
            } else {
                ContentUnavailableView {
                    Label("No Group Selected".localized(language: selectedLanguage), systemImage: "folder")
                } description: {
                    Text("Select a group from the sidebar or create a new one.".localized(language: selectedLanguage))
                } actions: {
                    if store.groups.isEmpty {
                        Button("Add Group".localized(language: selectedLanguage)) {
                            store.columnVisibility = .all
                            store.isAddingGroup = true
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SettingsChromePalette.windowBackground(for: colorScheme))
            }
        }
        .navigationTitle("App Groups".localized(language: selectedLanguage))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    store.columnVisibility = store.columnVisibility == .detailOnly ? .all : .detailOnly
                } label: {
                    Label("Toggle Sidebar".localized(language: selectedLanguage), systemImage: "sidebar.left")
                }
                .help("Toggle Sidebar".localized(language: selectedLanguage))
            }
        }
        .background(SettingsChromePalette.windowBackground(for: colorScheme))
        .onChange(of: store.selectedGroupId) { _, newValue in
            if pendingSelectedGroupId == newValue {
                pendingSelectedGroupId = nil
                pendingSelectionRequestID = nil
                return
            }

            // External selection changes (menu commands, URL routing, etc.) should win immediately.
            pendingSelectedGroupId = nil
            pendingSelectionRequestID = nil

            if let newValue {
                GroupSwitchPerformanceTracker.shared.beginGroupSwitch(
                    to: newValue,
                    source: "external",
                    expectedGroupIconCount: appCount(for: newValue)
                )
            }
        }
    }
}

// MARK: - Settings Content Split View

/// Own the content split independently of the window toolbar. NavigationSplitView
/// also divides the title bar, which moves the outer TabView's tabs on page changes.
struct SettingsGroupSplitView<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var detail: Detail

    func makeNSViewController(context: Context) -> SettingsGroupSplitController {
        let controller = SettingsGroupSplitController()
        updateNSViewController(controller, context: context)
        return controller
    }

    func updateNSViewController(_ controller: SettingsGroupSplitController, context: Context) {
        // Separate hosting controllers need the same environment as the surrounding
        // SwiftUI views, including the store, appearance and selected language.
        controller.sidebarHost.rootView = AnyView(sidebar.environment(\.self, context.environment))
        controller.detailHost.rootView = AnyView(detail.environment(\.self, context.environment))
        let requestedVisibility = columnVisibility
        controller.onVisibilityChange = { collapsed in
            // A newer store request wins over a deferred native layout callback.
            guard columnVisibility == requestedVisibility else { return }
            let visibility: NavigationSplitViewVisibility = collapsed ? .detailOnly : .all
            if columnVisibility != visibility { columnVisibility = visibility }
        }
        controller.setSidebarCollapsed(columnVisibility == .detailOnly)
    }

    static func dismantleNSViewController(_ controller: SettingsGroupSplitController, coordinator: ()) {
        controller.onVisibilityChange = nil
    }
}

@MainActor
final class SettingsGroupSplitController: NSSplitViewController {
    let sidebarHost = NSHostingController(rootView: AnyView(EmptyView()))
    let detailHost = NSHostingController(rootView: AnyView(EmptyView()))
    var onVisibilityChange: ((Bool) -> Void)?
    private var collapseObservation: NSKeyValueObservation?
    private var appliedInitialWidth = false
    private var applyingVisibility = false

    init() {
        super.init(nibName: nil, bundle: nil)
        splitView = SettingsContentSplitView()
        // The split items own sizing; their hosted SwiftUI content fills each pane.
        sidebarHost.sizingOptions = []
        detailHost.sizingOptions = []
        (sidebarHost.view as? NSHostingView<AnyView>)?.sizingOptions = []
        (detailHost.view as? NSHostingView<AnyView>)?.sizingOptions = []
        // A content item remains collapsible, but does not reserve a sidebar
        // section in the window's title bar as the .sidebar behavior would.
        let sidebar = NSSplitViewItem(viewController: sidebarHost)
        sidebar.canCollapse = true
        sidebar.minimumThickness = 220
        sidebar.allowsFullHeightLayout = false
        // Prefer keeping the sidebar width on window resize without outranking
        // AppKit's constraints for a user dragging the divider.
        sidebar.holdingPriority = NSLayoutConstraint.Priority(260)
        addSplitViewItem(sidebar)
        let detail = NSSplitViewItem(viewController: detailHost)
        detail.minimumThickness = 300
        addSplitViewItem(detail)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        collapseObservation = sidebar.observe(\.isCollapsed, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, !self.applyingVisibility else { return }
                self.scheduleVisibilityUpdate()
            }
        }
    }

    private func scheduleVisibilityUpdate() {
        // AppKit can change collapse state during layout. Publish after that
        // pass and read the latest state so rapid toggles cannot write stale values.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onVisibilityChange?(self.splitViewItems[0].isCollapsed)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func toggleSidebar(_ sender: Any?) {
        splitViewItems[0].isCollapsed.toggle()
    }

    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        drawnRect.insetBy(dx: -4, dy: 0)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if !appliedInitialWidth, splitView.bounds.width > 0, !splitViewItems[0].isCollapsed {
            appliedInitialWidth = true
            splitView.setPosition(220, ofDividerAt: 0)
        }
    }

    func setSidebarCollapsed(_ collapsed: Bool) {
        guard splitViewItems[0].isCollapsed != collapsed else { return }
        applyingVisibility = true
        splitViewItems[0].isCollapsed = collapsed
        applyingVisibility = false
    }
}

/// Let the native divider receive pointer events around its thin visible line,
/// even when the adjacent SwiftUI hosting views otherwise win hit testing.
final class SettingsContentSplitView: NSSplitView {
    private var dividerGrabRect: NSRect? {
        guard arrangedSubviews.count == 2, let leading = arrangedSubviews.first,
              !isSubviewCollapsed(leading) else { return nil }
        return NSRect(x: leading.frame.maxX, y: bounds.minY,
                      width: dividerThickness, height: bounds.height).insetBy(dx: -4, dy: 0)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard let window, let rect = dividerGrabRect, rect.contains(localPoint),
              let leading = arrangedSubviews.first else {
            super.mouseDown(with: event)
            return
        }
        // Track through the native split view, retaining its collapse and width
        // constraints. Adjacent SwiftUI hosts otherwise intercept divider dragging.
        let offset = leading.frame.maxX - localPoint.x
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let position = convert(next.locationInWindow, from: nil).x + offset
            setPosition(position, ofDividerAt: 0)
            layoutSubtreeIfNeeded()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        if bounds.contains(localPoint), dividerGrabRect?.contains(localPoint) == true { return self }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if let rect = dividerGrabRect { addCursorRect(rect, cursor: .resizeLeftRight) }
    }
}

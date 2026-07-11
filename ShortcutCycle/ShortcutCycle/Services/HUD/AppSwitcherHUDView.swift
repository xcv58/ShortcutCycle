import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

enum HUDMotionPolicy {
    static func shouldAnimateSelection(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    static func iconScale(isActive: Bool, isHovering: Bool, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 1.0 }
        if isActive { return 1.15 }
        if isHovering { return 1.08 }
        return 1.0
    }
}

/// App switcher HUD overlay view
struct AppSwitcherHUDView: View {
    let apps: [HUDAppItem]
    let activeAppId: String
    let shortcutString: String?
    var onSelect: ((String) -> Void)? = nil
    
    @AppStorage("showShortcutInHUD") private var showShortcutInHUD = true
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        VStack(spacing: 20) {
            Group {
                if apps.count > 5 {
                    gridLayout
                } else {
                    horizontalListLayout
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    // Adaptive tint based on color scheme
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.3))
                    )
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            
            // Active App Name
            activeAppNameView
        }
        .padding(40)
        .preferredColorScheme(appTheme.colorScheme)
        .background(WindowAppearanceApplier(colorScheme: appTheme.colorScheme))
    }
    
    private var gridLayout: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(80), spacing: 30), count: 5), spacing: 30) {
                    ForEach(apps) { app in
                        hudButton(for: app)
                    }
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 10)
            }
            .frame(maxHeight: 700) // Increased height to prevent clipping for larger grids
            .onAppear { scrollToActive(proxy: proxy, animated: false, anchor: .center) }
            .onChange(of: activeAppId) { _, _ in
                scrollToActive(
                    proxy: proxy,
                    animated: HUDMotionPolicy.shouldAnimateSelection(reduceMotion: reduceMotion),
                    anchor: .center
                )
            }
        }
    }
    
    private var horizontalListLayout: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(apps) { app in
                        hudButton(for: app)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: 700)
            .onAppear { scrollToActive(proxy: proxy, animated: false, anchor: nil) }
            .onChange(of: activeAppId) { _, _ in
                scrollToActive(
                    proxy: proxy,
                    animated: HUDMotionPolicy.shouldAnimateSelection(reduceMotion: reduceMotion),
                    anchor: nil
                )
            }
        }
    }
    
    private var activeAppNameView: some View {
        VStack(spacing: 4) {
            if let activeApp = apps.first(where: { $0.id == activeAppId }) {
                Text(activeApp.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .foregroundColor(.primary)
            }
            
            if showShortcutInHUD, let shortcut = shortcutString {
                Text(shortcut)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            Capsule()
            .fill(.regularMaterial)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }

    @ViewBuilder
    private func hudButton(for app: HUDAppItem) -> some View {
        if let icon = app.icon {
            HUDAppButton(
                app: app,
                icon: icon,
                isActive: app.id == activeAppId,
                onSelect: onSelect
            )
            .id(app.id)
        }
    }
    
    private func scrollToActive(proxy: ScrollViewProxy, animated: Bool, anchor: UnitPoint?) {
        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                proxy.scrollTo(activeAppId, anchor: anchor)
            }
        } else {
            proxy.scrollTo(activeAppId, anchor: anchor)
        }
    }
}

struct HUDAppButton: View {
    let app: HUDAppItem
    let icon: NSImage
    let isActive: Bool
    var onSelect: ((String) -> Void)?

    @State private var isHovering = false

    var body: some View {
        Button {
            onSelect?(app.id)
        } label: {
            HUDItemView(
                icon: icon,
                isActive: isActive,
                isRunning: app.isRunning,
                isHovering: isHovering,
                size: 72
            )
        }
        .buttonStyle(.plain)
        // HUD arrow navigation is handled by HUDManager. Avoid creating a
        // SwiftUI focus-effect responder solely to suppress the system ring.
        .focusable(false)
        .background {
            HUDAppKitHoverTracker { hovering in
                isHovering = hovering
            }
        }
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct HUDAppKitHoverTracker: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> HUDAppKitHoverView {
        let view = HUDAppKitHoverView()
        view.onHoverChange = onHoverChange
        return view
    }

    func updateNSView(_ nsView: HUDAppKitHoverView, context: Context) {
        nsView.onHoverChange = onHoverChange
    }

    static func dismantleNSView(_ nsView: HUDAppKitHoverView, coordinator: ()) {
        nsView.stopTracking()
    }
}

final class HUDAppKitHoverView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private(set) var isHovering = false
    private(set) var managedTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    override func updateTrackingAreas() {
        if let managedTrackingArea {
            removeTrackingArea(managedTrackingArea)
        }

        super.updateTrackingAreas()

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        managedTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        updateHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        updateHovering(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func updateHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        onHoverChange?(hovering)
    }

    func stopTracking() {
        if let managedTrackingArea {
            removeTrackingArea(managedTrackingArea)
            self.managedTrackingArea = nil
        }
        // SwiftUI calls dismantleNSView while invalidating its graph. Do not
        // invoke the state callback from teardown or it can mutate @State
        // during graph destruction.
        isHovering = false
        onHoverChange = nil
    }
}

struct HUDItemView: View {
    let icon: NSImage
    let isActive: Bool
    let isRunning: Bool
    let isHovering: Bool
    var size: CGFloat = 72 // Default size

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .scaleEffect(
                HUDMotionPolicy.iconScale(
                    isActive: isActive,
                    isHovering: isHovering,
                    reduceMotion: reduceMotion
                )
            )
            .saturation(isActive ? 1.1 : (isRunning ? (isHovering ? 1.0 : 0.8) : 0.2)) // Grayscale if not running, slight color on hover
            .opacity(isActive ? 1.0 : (isRunning ? (isHovering ? 0.9 : 0.7) : 0.5)) // Dimmer if not running
            .blur(radius: 0)
            .overlay(alignment: .bottomTrailing) {
                 if !isRunning {
                     Image(systemName: "arrow.up.circle.fill")
                         .font(.system(size: 20))
                         .foregroundColor(.white)
                         .background(Circle().fill(Color.blue))
                         .offset(x: 4, y: 4)
                         .shadow(radius: 2)
                 }
            }
            .padding(12)
            .background(
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                        
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 0)
                    } else if isHovering {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
                }
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7),
                value: isActive
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovering)
    }
}

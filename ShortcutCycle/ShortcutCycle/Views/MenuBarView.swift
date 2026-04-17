import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif
import KeyboardShortcuts

/// Menu bar popover view showing quick access to groups
struct MenuBarView: View {
    @EnvironmentObject var store: GroupStore
    @StateObject private var launchAtLogin = LaunchAtLoginManager.shared
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage(WelcomeExperiencePolicy.hasDismissedWelcomeKey) private var hasDismissedWelcome = false

    var selectedLanguage: String = "system"
    #if DEBUG
    var screenshotHighlightedGroupID: UUID? = nil
    var screenshotRunningBundleIDs: Set<String>? = nil
    var screenshotLaunchAtLogin: Bool? = nil
    var screenshotThemeOverride: AppTheme? = nil
    #endif
    
    @State private var listHeight: CGFloat = 0
    @State private var runningBundleIDs = Set<String>()

    private var effectiveTheme: AppTheme {
        #if DEBUG
        screenshotThemeOverride ?? appTheme
        #else
        appTheme
        #endif
    }

    // MARK: - Group list sizing

    /// Approximate rendered height of a single `MenuBarGroupRow`
    /// (body-font HStack with `.padding(.vertical, 6)` → ~29pt).
    /// Update this if the row's padding or typography changes.
    private static let groupRowHeight: CGFloat = 29

    /// Maximum number of group rows visible without scrolling.
    /// Beyond this the ScrollView scrolls; the popover never grows further.
    private static let maxVisibleGroupRows = 10

    /// Height of the "No groups created yet" placeholder.
    private static let emptyGroupListHeight: CGFloat = 60

    /// Upper bound on the group-list frame — hard cap that always applies,
    /// regardless of whether the measured height arrived yet.
    private static var groupListMaxHeight: CGFloat {
        CGFloat(maxVisibleGroupRows) * groupRowHeight
    }

    /// First-paint height estimate for the group list.
    ///
    /// `MenuBarExtra` sizes its host window from the initial layout pass,
    /// which runs before `GeometryReader` can report the measured content
    /// height via `HeightPreferenceKey`. Falling back to `nil` there was
    /// non-deterministic across machines and sometimes produced a 0-height
    /// ScrollView that clipped all groups. Seeding the frame with a
    /// group-count-derived estimate gives the first pass a concrete size;
    /// the preference-driven update below then refines it to the exact
    /// measured value.
    private var estimatedListHeight: CGFloat {
        let count = store.groups.count
        let estimated = count == 0
            ? Self.emptyGroupListHeight
            : CGFloat(count) * Self.groupRowHeight
        return min(estimated, Self.groupListMaxHeight)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        #if DEBUG
        if let screenshotLaunchAtLogin {
            return .constant(screenshotLaunchAtLogin)
        }
        #endif

        return $launchAtLogin.isEnabled
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("ShortcutCycle")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            Divider()
            
            // Groups list
            ScrollView {
                VStack(spacing: 0) {
                    if store.groups.isEmpty {
                        Text("No groups created yet".localized(language: selectedLanguage))
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(store.groups) { group in
                            #if DEBUG
                            MenuBarGroupRow(
                                group: group,
                                runningBundleIDs: runningBundleIDs,
                                screenshotHighlighted: group.id == screenshotHighlightedGroupID
                            )
                            #else
                            MenuBarGroupRow(
                                group: group,
                                runningBundleIDs: runningBundleIDs
                            )
                            #endif
                        }
                    }
                }
                .background(
                    GeometryReader { geo in
                         Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
                    }
                )
            }
            .frame(height: listHeight > 0 ? min(listHeight, Self.groupListMaxHeight) : estimatedListHeight)
            .onPreferenceChange(HeightPreferenceKey.self) { height in
                listHeight = height
            }
            
            Divider()
            
            // Preferences
            #if DEBUG
            if ScreenshotMode.usesSyntheticControls {
                HStack(spacing: 12) {
                    Text("Open at Login".localized(language: selectedLanguage))
                    Spacer()
                    ScreenshotAccentSwitch(isOn: launchAtLoginBinding.wrappedValue)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else {
                Toggle("Open at Login".localized(language: selectedLanguage), isOn: launchAtLoginBinding)
                    .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            #else
            Toggle("Open at Login".localized(language: selectedLanguage), isOn: launchAtLoginBinding)
                .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            #endif
            
            Divider()
                .padding(.vertical, 4)
            
            // Theme selection
            HStack(spacing: 0) {
                Text("Appearance".localized(language: selectedLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
                
                Spacer()
                
                HStack(spacing: 2) {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            #if DEBUG
                            guard screenshotThemeOverride == nil else { return }
                            #endif
                            appTheme = theme
                        } label: {
                            Image(systemName: theme.icon)
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(effectiveTheme == theme ? Color.accentColor : Color.clear)
                                .foregroundColor(effectiveTheme == theme ? .white : .primary)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(theme.displayName.localized(language: selectedLanguage))
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 4)
            
            Divider()
                .padding(.vertical, 4)
            
            // Settings button
            MenuBarButton(title: "Settings...".localized(language: selectedLanguage), icon: "gear") {
                ShortcutCycleURLRouter.openSettingsFromOutsideView()
            }

            if WelcomeExperiencePolicy.shouldShowReplayControl(hasDismissedWelcome: hasDismissedWelcome) {
                MenuBarButton(title: "Show welcome again".localized(language: selectedLanguage), icon: "sparkles") {
                    WelcomeExperiencePolicy.prepareReplay()
                    ShortcutCycleURLRouter.openSettingsFromOutsideView(tab: .groups)
                }
            }

            MenuBarButton(title: "Quit".localized(language: selectedLanguage), icon: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 280)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .background(WindowAppearanceApplier(colorScheme: effectiveTheme.colorScheme))
        .preferredColorScheme(effectiveTheme.colorScheme)
        .onAppear {
            refreshRunningBundleIDs()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshRunningBundleIDs()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshRunningBundleIDs()
        }
    }

    private func refreshRunningBundleIDs() {
        #if DEBUG
        if let screenshotRunningBundleIDs {
            runningBundleIDs = screenshotRunningBundleIDs
            return
        }
        #endif

        runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap { app in
                guard app.activationPolicy == .regular else { return nil }
                return app.bundleIdentifier
            }
        )
    }
}

/// A generic menu bar button with hover effect
struct MenuBarButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.accentColor : Color.clear)
        .foregroundColor(isHovering ? .white : .primary)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// A single group row in the menu bar view
struct MenuBarGroupRow: View {
    let group: AppGroup
    let runningBundleIDs: Set<String>
    #if DEBUG
    var screenshotHighlighted: Bool = false
    #endif
    @EnvironmentObject var store: GroupStore
    @State private var isHovering = false
    
    var body: some View {
        #if DEBUG
        let highlighted = screenshotHighlighted || isHovering
        #else
        let highlighted = isHovering
        #endif

        HStack(spacing: 8) {
            // Enable/Disable Toggle
            #if DEBUG
            if ScreenshotMode.usesSyntheticControls {
                ScreenshotAccentSwitch(isOn: group.isEnabled, size: .mini)
            } else {
                Toggle("", isOn: Binding(
                    get: { group.isEnabled },
                    set: { _ in store.toggleGroupEnabled(group) }
                ))
                .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
                .tint(.accentColor)
                .labelsHidden()
                .controlSize(.mini)
            }
            #else
            Toggle("", isOn: Binding(
                get: { group.isEnabled },
                set: { _ in store.toggleGroupEnabled(group) }
            ))
            .toggleStyle(SwitchToggleStyle(tint: Color(nsColor: .controlAccentColor)))
            .tint(.accentColor)
            .labelsHidden()
            .controlSize(.mini)
            #endif
            
            Image(systemName: "folder.fill")
                .foregroundColor(group.isEnabled ? (highlighted ? .white : .accentColor) : .gray)
            
            Text(group.name)
                .foregroundColor(group.isEnabled ? (highlighted ? .white : .primary) : .secondary)
            
            Spacer()
            
            if let shortcutString = group.shortcutDisplayString {
                Text(shortcutString)
                    .font(.caption)
                    .foregroundColor(highlighted ? .white.opacity(0.8) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        highlighted ? Color.white.opacity(0.2) : Color.gray.opacity(0.1)
                    )
                    .cornerRadius(4)
            }
            
            if hasRunningApp {
                Circle()
                    .fill(group.isEnabled ? (highlighted ? .white : Color.green) : Color.gray)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(highlighted ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var hasRunningApp: Bool {
        group.apps.contains { runningBundleIDs.contains($0.bundleIdentifier) }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

#Preview {
    MenuBarView()
        .environmentObject(GroupStore.shared)
}

struct WindowAppearanceApplier: NSViewRepresentable {
    var colorScheme: ColorScheme?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            updateWindowAppearance(for: view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            updateWindowAppearance(for: nsView)
        }
    }
    
    private func updateWindowAppearance(for view: NSView) {
        guard let window = view.window else { return }
        
        if let colorScheme = colorScheme {
            window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        } else {
            window.appearance = nil // Reset to system
        }
    }
}

struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

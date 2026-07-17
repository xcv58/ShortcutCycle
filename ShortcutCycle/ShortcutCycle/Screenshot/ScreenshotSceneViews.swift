#if DEBUG
import AppKit
import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

struct ScreenshotSceneContainerView: View {
    @EnvironmentObject private var store: GroupStore

    let arguments: ScreenshotArguments
    let localeObserver: LocaleObserver

    var body: some View {
        Group {
            if ScreenshotMode.usesSyntheticControls {
                content
                    .tint(.accentColor)
            } else {
                content
            }
        }
        .environment(\.controlActiveState, .key)
        .overlay(alignment: .topLeading) {
            if arguments.scene.showsTrafficLightsOverlay && ScreenshotMode.usesSyntheticChrome {
                ScreenshotTrafficLightsOverlay()
                    .padding(.top, 14)
                    .padding(.leading, 16)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch arguments.scene {
        case .general:
            if arguments.prefersLiveWindowCapture {
                MainView()
                    .environmentObject(store)
                    .environmentObject(localeObserver)
            } else {
                ScreenshotGeneralSceneView(localeObserver: localeObserver)
                    .environmentObject(store)
            }
        case .group:
            if arguments.prefersLiveWindowCapture {
                MainView()
                    .environmentObject(store)
                    .environmentObject(localeObserver)
            } else {
                ScreenshotGroupSceneView()
                    .environmentObject(store)
            }
        case .backups:
            if arguments.prefersLiveWindowCapture {
                MainView()
                    .environmentObject(store)
                    .environmentObject(localeObserver)
            } else {
                ScreenshotBackupSceneView(localeObserver: localeObserver)
                    .environmentObject(store)
            }
        case .hudHorizontal, .hudGrid:
            ScreenshotHUDSceneView(arguments: arguments)
        case .menuPopover:
            ScreenshotMenuPopoverSceneView(arguments: arguments)
                .environmentObject(store)
        }
    }
}

struct ScreenshotBackupSceneView: View {
    @EnvironmentObject private var store: GroupStore
    @Environment(\.colorScheme) private var colorScheme

    let localeObserver: LocaleObserver

    var body: some View {
        ZStack {
            ScreenshotGeneralSceneView(localeObserver: localeObserver)
                .environmentObject(store)
                .allowsHitTesting(false)

            Color.black.opacity(colorScheme == .dark ? 0.10 : 0.08)
                .ignoresSafeArea()

            BackupBrowserView()
                .environmentObject(store)
                .frame(width: 650, height: 450)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.38 : 0.18),
                    radius: colorScheme == .dark ? 42 : 30,
                    x: 0,
                    y: colorScheme == .dark ? 18 : 12
                )
        }
    }
}

struct ScreenshotGeneralSceneView: View {
    @EnvironmentObject private var store: GroupStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"

    let localeObserver: LocaleObserver

    var body: some View {
        ScreenshotSettingsWindowChrome(selectedLanguage: selectedLanguage, selectedTab: .general) {
            GeneralSettingsView()
                .environmentObject(store)
                .environmentObject(localeObserver)
        }
        .background(SettingsChromePalette.windowBackground(for: colorScheme))
    }
}

struct ScreenshotTrafficLightsOverlay: View {
    private let colors: [Color] = [
        Color(red: 1.0, green: 0.37, blue: 0.34),
        Color(red: 1.0, green: 0.74, blue: 0.18),
        Color(red: 0.18, green: 0.82, blue: 0.35)
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(colors.indices, id: \.self) { index in
                Circle()
                    .fill(colors[index])
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                    )
            }
        }
    }
}

struct ScreenshotGroupSceneView: View {
    @EnvironmentObject private var store: GroupStore
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @Environment(\.colorScheme) private var colorScheme

    private var selectedGroupID: UUID? {
        store.selectedGroupId ?? store.groups.first?.id
    }

    var body: some View {
        ScreenshotSettingsWindowChrome(selectedLanguage: selectedLanguage, selectedTab: .groups) {
            HStack(spacing: 0) {
                ScreenshotGroupSidebar(selectedGroupID: selectedGroupID)
                    .frame(width: 220)

                Divider()

                if let selectedGroupID {
                    GroupEditView(groupId: selectedGroupID)
                        .environmentObject(store)
                } else {
                    Color.clear
                }
            }
        }
        .background(SettingsChromePalette.windowBackground(for: colorScheme))
    }
}

struct ScreenshotHUDSceneView: View {
    let arguments: ScreenshotArguments

    private var items: [HUDAppItem] {
        ScreenshotFixtureLibrary.hudItems(for: arguments.groupKey ?? .info)
    }

    private var activeItemID: String {
        switch arguments.scene {
        case .hudGrid:
            return items.dropFirst(3).first?.id ?? items.first?.id ?? ""
        default:
            return items.first?.id ?? ""
        }
    }

    var body: some View {
        ZStack {
            ScreenshotBackdrop(theme: arguments.theme, backgroundURL: arguments.backgroundURL)
            AppSwitcherHUDView(
                apps: items,
                activeAppId: activeItemID,
                shortcutString: "⌥ + \(items.firstIndex(where: { $0.id == activeItemID }).map { String($0 + 1) } ?? "1")"
            )
            .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(arguments.theme.colorScheme)
    }
}

struct ScreenshotBackdrop: View {
    let theme: AppTheme
    let backgroundURL: URL?

    private var backgroundImage: NSImage? {
        guard let backgroundURL else { return nil }
        return NSImage(contentsOf: backgroundURL)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let backgroundImage {
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ForEach(backgroundShapes.indices, id: \.self) { index in
                        Circle()
                            .fill(backgroundShapes[index].color)
                            .frame(width: backgroundShapes[index].size, height: backgroundShapes[index].size)
                            .blur(radius: 40)
                            .offset(backgroundShapes[index].offset)
                    }
                }
            }
        }
    }

    private var gradientColors: [Color] {
        if theme == .dark {
            return [
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.12, green: 0.16, blue: 0.25),
                Color(red: 0.10, green: 0.23, blue: 0.29)
            ]
        }

        return [
            Color(red: 0.91, green: 0.96, blue: 1.0),
            Color(red: 0.84, green: 0.92, blue: 0.98),
            Color(red: 0.93, green: 0.96, blue: 0.89)
        ]
    }

    private var backgroundShapes: [(size: CGFloat, offset: CGSize, color: Color)] {
        if theme == .dark {
            return [
                (420, CGSize(width: -380, height: -240), Color.cyan.opacity(0.18)),
                (320, CGSize(width: 360, height: -180), Color.blue.opacity(0.18)),
                (500, CGSize(width: 280, height: 260), Color.green.opacity(0.12))
            ]
        }

        return [
            (420, CGSize(width: -360, height: -260), Color.white.opacity(0.55)),
            (300, CGSize(width: 320, height: -160), Color.cyan.opacity(0.22)),
            (440, CGSize(width: 260, height: 260), Color.green.opacity(0.18))
        ]
    }
}

struct ScreenshotMenuPopoverSceneView: View {
    @EnvironmentObject private var store: GroupStore

    let arguments: ScreenshotArguments

    private var selectedGroupID: UUID? {
        switch arguments.menuVariant {
        case .default:
            return nil
        case .selected:
            return arguments.groupKey.flatMap(ScreenshotFixtureLibrary.groupID(for:))
                ?? ScreenshotFixtureLibrary.groupID(for: .utilities)
        }
    }

    var body: some View {
        ZStack {
            Color(nsColor: arguments.theme == .dark ? .windowBackgroundColor : .underPageBackgroundColor)
                .ignoresSafeArea()

            VStack {
                Spacer(minLength: 90)
                MenuBarView(
                    selectedLanguage: arguments.language,
                    screenshotHighlightedGroupID: selectedGroupID,
                    screenshotLaunchAtLogin: true,
                    screenshotThemeOverride: arguments.theme
                )
                .fixedSize()
                .environmentObject(store)
                Spacer()
            }
        }
        .preferredColorScheme(arguments.theme.colorScheme)
    }
}
#endif

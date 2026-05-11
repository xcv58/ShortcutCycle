#if DEBUG
import Foundation
import SwiftUI

// MARK: - Screenshot Mode

enum ScreenshotMode {
    static let isActive = ProcessInfo.processInfo.arguments.contains("--screenshot-scene")
    static var renderStyle: ScreenshotRenderStyle = .synthetic

    static var usesSyntheticControls: Bool {
        isActive && renderStyle == .synthetic
    }

    static var usesSyntheticChrome: Bool {
        isActive && renderStyle == .synthetic
    }
}

enum ScreenshotRenderStyle {
    case liveWindow
    case synthetic
}

// MARK: - Screenshot Arguments

enum ScreenshotScene: String {
    case general
    case group
    case backups
    case hudHorizontal = "hud-horizontal"
    case hudGrid = "hud-grid"
    case menuPopover = "menu-popover"

    var defaultGroupKey: ScreenshotFixtureGroupKey? {
        switch self {
        case .general, .backups, .menuPopover:
            return nil
        case .group:
            return .utilities
        case .hudHorizontal:
            return .info
        case .hudGrid:
            return .manyApps
        }
    }

    var baseCaptureDelay: TimeInterval {
        switch self {
        case .backups:
            return 1.2
        case .general, .group:
            return 0.8
        case .hudHorizontal, .hudGrid, .menuPopover:
            return 0.45
        }
    }

    var hidesWindowChrome: Bool {
        switch self {
        case .hudHorizontal, .hudGrid, .menuPopover:
            return true
        case .general, .group, .backups:
            return false
        }
    }

    var showsTrafficLightsOverlay: Bool {
        switch self {
        case .general, .group, .backups:
            return true
        case .hudHorizontal, .hudGrid, .menuPopover:
            return false
        }
    }
}

enum ScreenshotFixtureGroupKey: String {
    case info
    case communication
    case productivity
    case utilities
    case media
    case manyApps = "many-apps"
}

enum ScreenshotMenuVariant: String {
    case `default`
    case selected
}

struct ScreenshotArguments {
    let scene: ScreenshotScene
    let theme: AppTheme
    let language: String
    let outputURL: URL
    let windowInfoURL: URL?
    let backgroundURL: URL?
    let groupKey: ScreenshotFixtureGroupKey?
    let menuVariant: ScreenshotMenuVariant

    var prefersLiveWindowCapture: Bool {
        windowInfoURL != nil
    }

    var captureDelay: TimeInterval {
        let themeSettleDelay: TimeInterval
        switch scene {
        case .general:
            themeSettleDelay = theme == .dark ? 0.55 : 0.2
        case .group:
            themeSettleDelay = theme == .dark ? 1.05 : 0.35
        case .backups:
            themeSettleDelay = theme == .dark ? 0.75 : 0.3
        case .hudHorizontal, .hudGrid, .menuPopover:
            themeSettleDelay = 0
        }

        return scene.baseCaptureDelay + themeSettleDelay
    }

    static let current = parse(CommandLine.arguments)

    private static func parse(_ arguments: [String]) -> ScreenshotArguments? {
        func value(for flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        guard let rawScene = value(for: "--screenshot-scene"),
              let scene = ScreenshotScene(rawValue: rawScene),
              let rawOutput = value(for: "--screenshot-output") else {
            return nil
        }

        let theme = AppTheme(rawValue: value(for: "--screenshot-theme") ?? "") ?? .light
        let language = value(for: "--screenshot-language") ?? "en"
        let windowInfoURL = value(for: "--screenshot-window-info").map { URL(fileURLWithPath: $0) }
        let backgroundURL = value(for: "--screenshot-background").map { URL(fileURLWithPath: $0) }
        let groupKey = value(for: "--screenshot-group").flatMap(ScreenshotFixtureGroupKey.init(rawValue:))
            ?? scene.defaultGroupKey
        let menuVariant = value(for: "--screenshot-variant").flatMap(ScreenshotMenuVariant.init(rawValue:))
            ?? .default

        return ScreenshotArguments(
            scene: scene,
            theme: theme,
            language: language,
            outputURL: URL(fileURLWithPath: rawOutput),
            windowInfoURL: windowInfoURL,
            backgroundURL: backgroundURL,
            groupKey: groupKey,
            menuVariant: menuVariant
        )
    }
}
#endif

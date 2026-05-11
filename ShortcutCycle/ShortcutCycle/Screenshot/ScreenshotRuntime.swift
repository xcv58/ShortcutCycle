#if DEBUG
import AppKit
import CoreGraphics
import Foundation
import KeyboardShortcuts
import SwiftUI
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

struct ScreenshotWindowInfo: Encodable {
    let windowNumber: Int
}

enum ScreenshotError: LocalizedError {
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureFailed(let message):
            return message
        }
    }
}

enum ScreenshotRuntime {
    static let windowSize = CGSize(width: 1440, height: 900)
    static let outputPixelSize = CGSize(width: 2880, height: 1800)

    private static let screenshotShortcutKeys: [KeyboardShortcuts.Key] = [
        .one, .two, .three, .four, .five, .six
    ]

    @MainActor
    static func makeStore() -> GroupStore {
        GroupStore(
            userDefaults: .standard,
            backupDebounceInterval: 3600,
            saveDebounceInterval: 0,
            autoBackupEnabled: false
        )
    }

    static func primeDefaults(for arguments: ScreenshotArguments) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: WelcomeExperiencePolicy.hasDismissedWelcomeKey)
        defaults.set(true, forKey: WelcomeExperiencePolicy.hasAutoOpenedWelcomeSettingsKey)
        defaults.set(arguments.language, forKey: "selectedLanguage")
        defaults.set(arguments.theme.rawValue, forKey: "appTheme")
        defaults.set(true, forKey: "showHUD")
        defaults.set(true, forKey: "showShortcutInHUD")
        WelcomeExperiencePolicy.isScreenshotModeEnabled = true
        ScreenshotMode.renderStyle = arguments.prefersLiveWindowCapture ? .liveWindow : .synthetic
        LanguageManager.shared.syncAppleLanguages(for: arguments.language)
    }

    @MainActor
    static func seed(store: GroupStore, for arguments: ScreenshotArguments) {
        let groups = ScreenshotFixtureLibrary.makeGroups()
        RunningAppQuickAddCatalog.shared.setOverrideApps(ScreenshotFixtureLibrary.makeQuickAddOverrideApps())
        let export = ScreenshotFixtureLibrary.makeExport(
            groups: groups,
            theme: arguments.theme,
            language: arguments.language
        )
        store.applyImport(export)

        if let groupKey = arguments.groupKey,
           let groupID = ScreenshotFixtureLibrary.groupID(for: groupKey) {
            store.selectedGroupId = groupID
        }

        if arguments.scene == .backups {
            ScreenshotFixtureLibrary.writeBackupFixtures(
                into: store,
                groups: groups,
                language: arguments.language,
                theme: arguments.theme
            )
        }

        switch arguments.scene {
        case .general:
            ShortcutCycleURLNavigationState.request(tab: .general)
        case .group:
            ShortcutCycleURLNavigationState.request(tab: .groups)
        case .backups:
            ShortcutCycleURLNavigationState.request(tab: .general)
        case .hudHorizontal, .hudGrid, .menuPopover:
            break
        }
    }

    static func shortcutDataMap(for groups: [AppGroup]) -> [String: ShortcutData] {
        var shortcuts: [String: ShortcutData] = [:]

        for (index, group) in groups.enumerated() where screenshotShortcutKeys.indices.contains(index) {
            let shortcut = KeyboardShortcuts.Shortcut(screenshotShortcutKeys[index], modifiers: [.option])
            shortcuts[group.id.uuidString] = ShortcutData(
                carbonKeyCode: shortcut.carbonKeyCode,
                carbonModifiers: shortcut.carbonModifiers
            )
        }

        return shortcuts
    }

    @MainActor
    static func capture(window: NSWindow, arguments: ScreenshotArguments) async throws {
        prepare(window: window)

        let screenshot: CGImage
        do {
            if let liveSnapshot = try await systemSnapshot(window: window) {
                screenshot = liveSnapshot
            } else if let cachedSnapshot = snapshot(window: window) {
                screenshot = cachedSnapshot
            } else {
                throw ScreenshotError.captureFailed("Failed to snapshot screenshot window")
            }
        } catch {
            if let cachedSnapshot = snapshot(window: window) {
                fputs("Falling back to cached screenshot capture: \(error.localizedDescription)\n", stderr)
                screenshot = cachedSnapshot
            } else {
                throw error
            }
        }

        let composited = try compositeToOutputCanvas(cgImage: screenshot, theme: arguments.theme)
        try write(cgImage: composited, to: arguments.outputURL)
    }

    #if canImport(ScreenCaptureKit)
    @MainActor
    private static func systemSnapshot(window: NSWindow) async throws -> CGImage? {
        guard #available(macOS 14.4, *) else { return nil }

        let content = try await SCShareableContent.currentProcess
        guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            return nil
        }

        let scale = max(window.backingScaleFactor, 1)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = false
        configuration.shouldBeOpaque = false

        let backgroundColor = CGColor(gray: 0, alpha: 0)
        configuration.backgroundColor = backgroundColor

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(throwing: ScreenshotError.captureFailed("ScreenCaptureKit returned no image"))
            }
        }
    }
    #else
    @MainActor
    private static func systemSnapshot(window: NSWindow) async throws -> CGImage? {
        nil
    }
    #endif

    @MainActor
    static func prepareForExternalCapture(window: NSWindow, arguments: ScreenshotArguments) throws {
        prepare(window: window)

        guard let windowInfoURL = arguments.windowInfoURL else { return }
        let directory = windowInfoURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = ScreenshotWindowInfo(windowNumber: window.windowNumber)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: windowInfoURL, options: .atomic)
    }

    @MainActor
    private static func prepare(window: NSWindow) {
        window.orderFrontRegardless()
        if window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        }
        if window.canBecomeMain {
            window.makeMain()
        }
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    static func configure(window: NSWindow, for arguments: ScreenshotArguments) {
        let size = NSSize(width: windowSize.width, height: windowSize.height)
        let usesLiveWindowChrome = arguments.prefersLiveWindowCapture && !arguments.scene.hidesWindowChrome
        if let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let origin = NSPoint(
                x: screenFrame.midX - (size.width / 2),
                y: screenFrame.midY - (size.height / 2)
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        } else {
            window.setFrame(NSRect(origin: .zero, size: size), display: true)
            window.center()
        }

        window.appearance = {
            guard let colorScheme = arguments.theme.colorScheme else { return nil }

            switch colorScheme {
            case .dark:
                return NSAppearance(named: .darkAqua)
            case .light:
                return NSAppearance(named: .aqua)
            @unknown default:
                return nil
            }
        }()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = arguments.scene.hidesWindowChrome || !usesLiveWindowChrome
        window.isMovableByWindowBackground = false
        window.isOpaque = !arguments.scene.hidesWindowChrome
        window.backgroundColor = arguments.scene.hidesWindowChrome ? .clear : .windowBackgroundColor
        window.hasShadow = !arguments.scene.hidesWindowChrome
        window.sharingType = .readOnly
        if usesLiveWindowChrome {
            window.toolbarStyle = .unified
        }

        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for buttonType in buttons {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            button.isHidden = !usesLiveWindowChrome
            button.showsBorderOnlyWhileMouseInside = false
            button.needsDisplay = true
        }

        window.standardWindowButton(.closeButton)?.superview?.needsDisplay = true

        if arguments.scene.hidesWindowChrome {
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    static func ensureOutputDirectory(for outputURL: URL) throws {
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func write(cgImage: CGImage, to outputURL: URL) throws {
        try ensureOutputDirectory(for: outputURL)
        let representation = NSBitmapImageRep(cgImage: cgImage)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.captureFailed("Failed to encode PNG data")
        }
        try data.write(to: outputURL, options: .atomic)
    }

    @MainActor
    private static func snapshot(window: NSWindow) -> CGImage? {
        guard let targetView = window.contentView?.superview ?? window.contentView else {
            return nil
        }

        targetView.layoutSubtreeIfNeeded()
        let bounds = targetView.bounds
        guard let rep = targetView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        targetView.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    private static func compositeToOutputCanvas(cgImage: CGImage, theme: AppTheme) throws -> CGImage {
        let outputWidth = Int(outputPixelSize.width)
        let outputHeight = Int(outputPixelSize.height)

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenshotError.captureFailed("Failed to create output CGContext")
        }

        let fillColor = theme == .dark ? NSColor.black : NSColor.white
        context.setFillColor(fillColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

        let originX = (outputWidth - cgImage.width) / 2
        let originY = (outputHeight - cgImage.height) / 2
        context.draw(
            cgImage,
            in: CGRect(x: originX, y: originY, width: cgImage.width, height: cgImage.height)
        )

        guard let outputImage = context.makeImage() else {
            throw ScreenshotError.captureFailed("Failed to create output CGImage")
        }

        return outputImage
    }
}
#endif

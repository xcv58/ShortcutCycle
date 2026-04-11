#if DEBUG
import AppKit
import Foundation
import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

@MainActor
enum ScreenshotWindowLifecycle {
    static var store: GroupStore?
    static var controller: NSWindowController?

    static func configure(store: GroupStore) {
        self.store = store
    }

    static func present(arguments: ScreenshotArguments) {
        guard let store else { return }

        if arguments.prefersLiveWindowCapture {
            switch arguments.scene {
            case .general:
                ShortcutCycleURLNavigationState.request(tab: .general)
            case .group:
                ShortcutCycleURLNavigationState.request(tab: .groups)
            case .backups:
                ShortcutCycleURLNavigationState.requestBackupBrowser()
            case .hudHorizontal, .hudGrid, .menuPopover:
                break
            }
        }

        let captureWindow: NSWindow
        switch arguments.scene {
        case .hudHorizontal where arguments.prefersLiveWindowCapture,
             .hudGrid where arguments.prefersLiveWindowCapture:
            self.controller = nil
            captureWindow = presentLiveHUDWindow(arguments: arguments)
        case .menuPopover where arguments.prefersLiveWindowCapture:
            captureWindow = presentLiveMenuPopoverWindow(arguments: arguments, store: store)
        default:
            captureWindow = presentSceneWindow(arguments: arguments, store: store)
        }

        let timeout = arguments.windowInfoURL == nil
            ? max(arguments.captureDelay + 4, 8.0)
            : max(arguments.captureDelay + 20, 25.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + arguments.captureDelay) {
            Task { @MainActor in
                do {
                    if arguments.windowInfoURL != nil {
                        try ScreenshotRuntime.prepareForExternalCapture(window: captureWindow, arguments: arguments)
                    } else {
                        try await ScreenshotRuntime.capture(window: captureWindow, arguments: arguments)
                        exit(0)
                    }
                } catch {
                    fputs("Screenshot capture failed: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            fputs("Screenshot capture timed out for scene \(arguments.scene.rawValue)\n", stderr)
            exit(2)
        }
    }

    private static func presentSceneWindow(arguments: ScreenshotArguments, store: GroupStore) -> NSWindow {
        let rootView = ScreenshotSceneContainerView(
            arguments: arguments,
            localeObserver: LocaleObserver()
        )
        .environmentObject(store)

        let hostingController = NSHostingController(rootView: rootView)
        let styleMask: NSWindow.StyleMask = arguments.scene.hidesWindowChrome
            ? [.borderless]
            : [.titled, .closable, .miniaturizable]
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ScreenshotRuntime.windowSize.width,
                height: ScreenshotRuntime.windowSize.height
            ),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.title = arguments.prefersLiveWindowCapture ? "Shortcut Cycle" : "ShortcutCycle Screenshot"
        window.isMovable = false

        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        ScreenshotRuntime.configure(window: window, for: arguments)
        return window
    }

    private static func presentLiveHUDWindow(arguments: ScreenshotArguments) -> NSWindow {
        let groupKey = arguments.groupKey ?? arguments.scene.defaultGroupKey ?? .info
        let hudCapture = ScreenshotFixtureLibrary.hudCaptureState(for: arguments.scene, key: groupKey)

        guard let window = HUDManager.shared.presentScreenshotHUD(
            items: hudCapture.items,
            activeAppId: hudCapture.activeItemID,
            shortcut: hudCapture.shortcut
        ) else {
            fatalError("Failed to create HUD screenshot window")
        }

        return window
    }

    private static func presentLiveMenuPopoverWindow(arguments: ScreenshotArguments, store: GroupStore) -> NSWindow {
        let selectedGroupID: UUID? = {
            switch arguments.menuVariant {
            case .default:
                return nil
            case .selected:
                return arguments.groupKey.flatMap(ScreenshotFixtureLibrary.groupID(for:))
                    ?? ScreenshotFixtureLibrary.groupID(for: .utilities)
            }
        }()

        let rootView = MenuBarView(
            selectedLanguage: arguments.language,
            screenshotHighlightedGroupID: selectedGroupID,
            screenshotRunningBundleIDs: ScreenshotFixtureLibrary.menuRunningBundleIDs(),
            screenshotLaunchAtLogin: true,
            screenshotThemeOverride: arguments.theme
        )
        .environment(\.controlActiveState, .key)
        .environmentObject(store)

        let hostingController = NSHostingController(rootView: rootView)
        let window = ScreenshotPopoverCaptureWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 280, height: 400)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.isMovable = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.sharingType = .readOnly

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        if fittingSize.width > 0, fittingSize.height > 0 {
            window.setContentSize(fittingSize)
        }

        let controller = NSWindowController(window: window)
        self.controller = controller
        controller.showWindow(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()
        return window
    }
}

final class ScreenshotPopoverCaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
#endif

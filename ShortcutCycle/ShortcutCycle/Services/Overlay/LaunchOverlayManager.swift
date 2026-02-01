import Foundation
import AppKit
import SwiftUI

@MainActor
class LaunchOverlayManager {
    static let shared = LaunchOverlayManager()

    private var window: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    func show(appName: String, appIcon: NSImage?) {
        dismiss()

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true

        let view = NSHostingView(rootView: LaunchOverlayView(appName: appName, appIcon: appIcon))
        panel.contentView = view

        if let screen = NSScreen.main {
            let size = view.fittingSize
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.midY - size.height / 2
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }

        panel.alphaValue = 0
        panel.orderFront(nil)

        self.window = panel

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1.0
        }

        // Auto-dismiss after 1.0s with fade out
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let panel = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                self?.window = nil
            }
        })
    }
}

struct LaunchOverlayView: View {
    let appName: String
    let appIcon: NSImage?
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("selectedLanguage") private var selectedLanguage = "system"
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
            }

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)

                Text("Opening…".localized(language: selectedLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.3))
                )
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(40)
        .preferredColorScheme(appTheme.colorScheme)
    }
}

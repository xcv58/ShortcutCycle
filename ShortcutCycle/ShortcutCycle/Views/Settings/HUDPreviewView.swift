import AppKit
import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

/// A noninteractive sample of the real HUD, using original, unbranded icons.
struct HUDPreviewView: View {
    let showShortcut: Bool
    var selectedLanguage: String = "system"

    private let scale: CGFloat = 2.0 / 3.0

    var body: some View {
        HUDPreviewLayout(scale: scale) {
            HUDContentView(
                apps: HUDPreviewSample.allCases.map { sample in
                    HUDAppItem(
                        id: sample.rawValue,
                        name: sample.nameKey.localized(language: selectedLanguage),
                        icon: sample.icon,
                        isRunning: true
                    )
                },
                activeAppId: HUDPreviewSample.chat.rawValue,
                shortcutString: showShortcut ? "⌃ + ⌥ + ⌘ + C" : nil
            )
            .scaleEffect(scale, anchor: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Scale both the drawing and its layout footprint, leaving the live HUD's
/// spacing and typography intact and avoiding clipped shadows in the preview.
private struct HUDPreviewLayout: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }
}

/// Original vector illustrations; no installed app icons or branded assets.
private enum HUDPreviewSample: String, CaseIterable {
    case browser, chat, mail

    var nameKey: String {
        switch self {
        case .browser: return "HUD Preview Browser"
        case .chat: return "HUD Preview Chat"
        case .mail: return "HUD Preview Mail"
        }
    }

    var icon: NSImage { Self.icons[self]! }

    private static let icons: [HUDPreviewSample: NSImage] = Dictionary(
        uniqueKeysWithValues: allCases.map { sample in
            (sample, NSImage(size: NSSize(width: 72, height: 72), flipped: true) { _ in
                sample.drawIcon()
                return true
            })
        }
    )

    private func drawIcon() {
        let base: NSColor
        switch self {
        case .browser: base = NSColor(srgbRed: 0.12, green: 0.48, blue: 0.78, alpha: 1)
        case .chat: base = NSColor(srgbRed: 0.49, green: 0.30, blue: 0.75, alpha: 1)
        case .mail: base = NSColor(srgbRed: 0.86, green: 0.40, blue: 0.19, alpha: 1)
        }
        let tile = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 64, height: 64), xRadius: 15, yRadius: 15)
        NSGradient(starting: base.blended(withFraction: 0.18, of: .white) ?? base, ending: base)?
            .draw(in: tile, angle: 90)

        switch self {
        case .browser:
            fill(NSRect(x: 13, y: 17, width: 46, height: 38), radius: 5, color: .white)
            stroke([NSPoint(x: 13, y: 27), NSPoint(x: 59, y: 27)], color: base, width: 2)
            for x in [19.0, 25.0, 31.0] {
                fill(NSRect(x: x, y: 21, width: 3, height: 3), radius: 1.5, color: base)
            }
            fill(NSRect(x: 19, y: 33, width: 12, height: 16), radius: 2, color: base.withAlphaComponent(0.35))
            fill(NSRect(x: 35, y: 33, width: 17, height: 5), radius: 2, color: base.withAlphaComponent(0.65))
            fill(NSRect(x: 35, y: 43, width: 13, height: 4), radius: 2, color: base.withAlphaComponent(0.35))
        case .chat:
            fill(NSRect(x: 12, y: 15, width: 40, height: 28), radius: 7, color: .white.withAlphaComponent(0.55))
            fill(NSRect(x: 23, y: 29, width: 37, height: 27), radius: 7, color: .white)
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 44, y: 54))
            tail.line(to: NSPoint(x: 44, y: 62))
            tail.line(to: NSPoint(x: 53, y: 54))
            tail.close()
            NSColor.white.setFill()
            tail.fill()
            fill(NSRect(x: 30, y: 37, width: 23, height: 3), radius: 1.5, color: base)
            fill(NSRect(x: 30, y: 45, width: 16, height: 3), radius: 1.5, color: base.withAlphaComponent(0.55))
        case .mail:
            fill(NSRect(x: 12, y: 21, width: 48, height: 34), radius: 5, color: .white)
            stroke([NSPoint(x: 14, y: 24), NSPoint(x: 36, y: 41), NSPoint(x: 58, y: 24)], color: base, width: 3)
            stroke([NSPoint(x: 15, y: 52), NSPoint(x: 29, y: 39)], color: base.withAlphaComponent(0.4), width: 2)
            stroke([NSPoint(x: 57, y: 52), NSPoint(x: 43, y: 39)], color: base.withAlphaComponent(0.4), width: 2)
        }
    }

    private func fill(_ rect: NSRect, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    private func stroke(_ points: [NSPoint], color: NSColor, width: CGFloat) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: first)
        for point in points.dropFirst() { path.line(to: point) }
        path.lineWidth = width
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }
}

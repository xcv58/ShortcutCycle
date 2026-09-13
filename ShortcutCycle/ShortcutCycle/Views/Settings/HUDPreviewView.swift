import AppKit
import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

/// A noninteractive sample of the real HUD, using the original preview symbols.
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

/// The same SF Symbols as the original preview; no installed app icon lookups.
private enum HUDPreviewSample: String, CaseIterable {
    case browser, chat, mail

    var nameKey: String {
        switch self {
        case .browser: return "HUD Preview Browser"
        case .chat: return "HUD Preview Chat"
        case .mail: return "HUD Preview Mail"
        }
    }

    var icon: NSImage? { Self.icons[self] }

    private var symbolName: String {
        switch self {
        case .browser: return "safari.fill"
        case .chat: return "message.fill"
        case .mail: return "envelope.fill"
        }
    }

    private static let icons: [HUDPreviewSample: NSImage] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { sample in
            let color: NSColor = sample == .chat ? .systemGreen : .systemBlue
            let configuration = NSImage.SymbolConfiguration(pointSize: 72, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
                .applying(.preferringMonochrome())
            guard let icon = NSImage(systemSymbolName: sample.symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else {
                return nil
            }
            // Keep the blue/green symbol palette when rendered by the shared HUD.
            icon.isTemplate = false
            return (sample, icon)
        }
    )
}

import SwiftUI

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

struct ScreenshotAccentSwitch: View {
    enum Size {
        case regular
        case mini

        var trackSize: CGSize {
            switch self {
            case .regular:
                return CGSize(width: 38, height: 22)
            case .mini:
                return CGSize(width: 30, height: 18)
            }
        }

        var knobDiameter: CGFloat {
            switch self {
            case .regular:
                return 18
            case .mini:
                return 14
            }
        }

        var inset: CGFloat {
            switch self {
            case .regular:
                return 2
            case .mini:
                return 2
            }
        }
    }

    let isOn: Bool
    var size: Size = .regular

    var body: some View {
        let trackSize = size.trackSize
        let knobDiameter = size.knobDiameter
        let inset = size.inset

        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? Color(nsColor: .controlAccentColor) : Color.primary.opacity(0.18))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.black.opacity(isOn ? 0.08 : 0.10), lineWidth: 0.5)
                )

            Circle()
                .fill(.white)
                .frame(width: knobDiameter, height: knobDiameter)
                .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 0.8)
                .padding(inset)
        }
        .frame(width: trackSize.width, height: trackSize.height)
        .accessibilityHidden(true)
    }
}

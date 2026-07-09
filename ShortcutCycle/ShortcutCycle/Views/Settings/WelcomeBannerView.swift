import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

// MARK: - Welcome Banner

/// A one-time welcome callout shown at the top of the Settings window on first launch (and on replay).
/// The banner persists across Settings window sessions until the user explicitly dismisses it with ×.
struct WelcomeBannerView: View {
    let selectedLanguage: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "command.square.fill")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("ShortcutCycle is running in your menu bar".localized(language: selectedLanguage))
                    .font(.headline)

                Text("Look for the ShortcutCycle icon in the top-right menu bar whenever you want to open the app again.".localized(language: selectedLanguage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SettingsShortcutHUDTipView: View {
    let selectedLanguage: String
    let onCloseSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.max.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 4) {
                Text("Switching may feel slower while Settings is open".localized(language: selectedLanguage))
                    .font(.headline)

                Text("To avoid asking for extra macOS permissions, ShortcutCycle may briefly activate Settings while switching with the HUD enabled. Close Settings for normal switching speed.".localized(language: selectedLanguage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    hideTipButton
                    closeSettingsButton
                }

                VStack(alignment: .trailing, spacing: 8) {
                    hideTipButton
                    closeSettingsButton
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var closeSettingsButton: some View {
        Button("Close Settings Window".localized(language: selectedLanguage), action: onCloseSettings)
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
    }

    private var hideTipButton: some View {
        Button("Hide Tip".localized(language: selectedLanguage), action: onDismiss)
            .controlSize(.small)
    }
}

#Preview {
    VStack(spacing: 8) {
        WelcomeBannerView(selectedLanguage: "en", onDismiss: {})
        SettingsShortcutHUDTipView(selectedLanguage: "en", onCloseSettings: {}, onDismiss: {})
    }
    .padding()
    .frame(width: 620)
}

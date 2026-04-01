import SwiftUI
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

// MARK: - Welcome Banner

/// A one-time welcome card shown in the Groups tab on first launch (and on replay).
/// The banner is session-scoped: it disappears automatically when the Settings window closes.
struct WelcomeBannerView: View {
    let selectedLanguage: String

    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Headline
            Text("ShortcutCycle is running in your menu bar".localized(language: selectedLanguage))
                .font(.headline)

            // Mini menu bar mockup
            MenuBarMockupView()

            // Body text
            Text("Look for the ShortcutCycle icon in the top-right menu bar whenever you want to open the app again.".localized(language: selectedLanguage))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            // Open at Login toggle
            Toggle("Open at Login".localized(language: selectedLanguage), isOn: $launchAtLogin.isEnabled)
                .toggleStyle(.switch)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Menu Bar Mockup

/// A decorative mini menu bar strip illustrating where the ShortcutCycle icon lives.
private struct MenuBarMockupView: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            // Simulated system menu bar icons to the left of the app icon
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
                Image(systemName: "clock")
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.secondary)

            // ShortcutCycle icon (highlighted)
            Image(systemName: "command.square.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                .padding(.leading, 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}

#Preview {
    WelcomeBannerView(selectedLanguage: "en")
        .padding()
        .frame(width: 500)
}

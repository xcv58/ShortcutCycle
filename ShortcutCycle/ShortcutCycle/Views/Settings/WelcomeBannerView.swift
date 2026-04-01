import SwiftUI

// MARK: - Welcome Banner

/// A one-time welcome card shown in the Groups tab on first launch (and on replay).
/// The banner is session-scoped: it disappears automatically when the Settings window closes.
struct WelcomeBannerView: View {
    let selectedLanguage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "command.square.fill")
                .font(.system(size: 24))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 6) {
                Text("ShortcutCycle is running in your menu bar".localized(language: selectedLanguage))
                    .font(.headline)

                Text("Look for the ShortcutCycle icon in the top-right menu bar whenever you want to open the app again.".localized(language: selectedLanguage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Create your first group here, or turn on Open at Login so ShortcutCycle is always ready.".localized(language: selectedLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    WelcomeBannerView(selectedLanguage: "en")
        .padding()
        .frame(width: 500)
}

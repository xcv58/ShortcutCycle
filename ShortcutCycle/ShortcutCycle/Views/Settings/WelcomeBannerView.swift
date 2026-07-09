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

#Preview {
    WelcomeBannerView(selectedLanguage: "en", onDismiss: {})
    .padding()
    .frame(width: 620)
}

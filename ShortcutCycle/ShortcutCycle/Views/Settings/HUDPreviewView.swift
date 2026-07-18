import SwiftUI

/// A static preview of the HUD for settings
struct HUDPreviewView: View {
    let showShortcut: Bool
    var selectedLanguage: String = "system"
    @Environment(\.colorScheme) var colorScheme

    private var previewShellFill: Color {
        colorScheme == .dark
            ? SettingsChromePalette.panelBackground(for: colorScheme)
            : Color.white.opacity(0.42)
    }

    private var previewShellBorder: Color {
        colorScheme == .dark
            ? SettingsChromePalette.panelBorder(for: colorScheme)
            : Color.primary.opacity(0.10)
    }

    private var selectedTileFill: Color {
        colorScheme == .dark
            ? SettingsChromePalette.inlineFill(for: colorScheme)
            : Color.primary.opacity(0.05)
    }

    private var selectedTileBorder: Color {
        colorScheme == .dark
            ? SettingsChromePalette.panelBorder(for: colorScheme)
            : Color.primary.opacity(0.10)
    }

    private var shortcutCapsuleFill: Color {
        colorScheme == .dark
            ? SettingsChromePalette.inlineFill(for: colorScheme)
            : Color.white.opacity(0.72)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Icons Row
            HStack(spacing: 16) {
                // Mock icons
                Image(systemName: "safari.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundColor(.blue)
                    .padding(8)
                    .opacity(0.6)
                
                Image(systemName: "message.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundColor(.green)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedTileFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selectedTileBorder, lineWidth: 1)
                    )
                    .shadow(
                        color: colorScheme == .dark ? .black.opacity(0.18) : .black.opacity(0.10),
                        radius: colorScheme == .dark ? 10 : 4,
                        x: 0,
                        y: colorScheme == .dark ? 6 : 2
                    )
                    .scaleEffect(1.1)
                
                Image(systemName: "envelope.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundColor(.blue)
                    .padding(8)
                    .opacity(0.6)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(previewShellFill)
                    .shadow(
                        color: colorScheme == .dark ? .black.opacity(0.24) : .black.opacity(0.10),
                        radius: colorScheme == .dark ? 18 : 10,
                        x: 0,
                        y: colorScheme == .dark ? 10 : 4
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(previewShellBorder, lineWidth: 1)
            )
            
            // App Name Label
            VStack(spacing: 2) {
                Text("Messages")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if showShortcut {
                    Text("⌃ + ⌥ + ⌘ + C")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(shortcutCapsuleFill)
            )
            .overlay(
                Capsule()
                    .stroke(previewShellBorder.opacity(colorScheme == .dark ? 0.85 : 0.65), lineWidth: 1)
            )
        }
        .accessibilityHidden(true)
    }
}

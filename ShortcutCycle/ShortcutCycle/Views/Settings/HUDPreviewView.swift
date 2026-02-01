import SwiftUI

/// A static preview of the HUD for settings
struct HUDPreviewView: View {
    let showShortcut: Bool
    var selectedLanguage: String = "system"
    @Environment(\.colorScheme) var colorScheme
    
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
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            
            // App Name Label
            VStack(spacing: 2) {
                Text("Messages")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if showShortcut {
                    Text("⌃ ⌥ ⌘  C")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.regularMaterial)
            )
        }
    }
}

import SwiftUI
import Carbon.HIToolbox

/// A view that records keyboard shortcuts
struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcutData?
    @State private var isRecording = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                isRecording.toggle()
                isFocused = isRecording
            }) {
                HStack {
                    if isRecording {
                        Text("Press keys...")
                            .foregroundColor(.secondary)
                    } else if let shortcut = shortcut {
                        Text(shortcut.displayString)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    } else {
                        Text("Click to record")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minWidth: 140)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRecording ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .focusable()
            .focused($isFocused)
            .onKeyPress { keyPress in
                guard isRecording else { return .ignored }
                
                // We need at least one modifier key
                let modifiers = keyPress.modifiers
                guard !modifiers.isEmpty else { return .ignored }
                
                // Get the key code and modifiers from the underlying NSEvent
                if let event = NSApp.currentEvent {
                    let carbonMods = ShortcutManager.carbonModifiers(from: event.modifierFlags)
                    shortcut = KeyboardShortcutData(
                        keyCode: UInt32(event.keyCode),
                        modifiers: carbonMods
                    )
                    isRecording = false
                    isFocused = false
                }
                
                return .handled
            }
            
            if shortcut != nil {
                Button(action: {
                    shortcut = nil
                    isRecording = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var shortcut: KeyboardShortcutData?
        
        var body: some View {
            ShortcutRecorderView(shortcut: $shortcut)
                .padding()
        }
    }
    
    return PreviewWrapper()
}

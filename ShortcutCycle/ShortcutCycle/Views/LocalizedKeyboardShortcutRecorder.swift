import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

/// A custom recorder that uses a transient AppKit popover and a local event monitor.
///
/// `KeyboardShortcuts.RecorderCocoa` relies on AppKit field-editor behavior that no
/// longer receives recording events reliably in SwiftUI settings windows on macOS 27.
/// Capturing the event in a transient popover matches the implementation used by
/// MacTools while preserving KeyboardShortcuts for persistence and global handling.
struct LocalizedKeyboardShortcutRecorder: View {
    let name: KeyboardShortcuts.Name
    let selectedLanguage: String
    let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    @State private var isRecording = false

    init(
        name: KeyboardShortcuts.Name,
        selectedLanguage: String,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.name = name
        self.selectedLanguage = selectedLanguage
        self.onChange = onChange
    }

    private var shortcut: KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: name)
    }

    private var displayText: String {
        if isRecording {
            return "Press Shortcut".localized(language: selectedLanguage)
        }

        return shortcut?.description ?? "Record Shortcut".localized(language: selectedLanguage)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording = true
            } label: {
                Text(displayText)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(shortcut == nil && !isRecording ? .tertiary : .primary)
                    .frame(minWidth: 128, alignment: .center)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("Keyboard Shortcut".localized(language: selectedLanguage)))

            if shortcut != nil {
                Button {
                    saveShortcut(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Delete".localized(language: selectedLanguage)))
                .help("Delete".localized(language: selectedLanguage))
            }
        }
        .background {
            ShortcutRecorderPopoverAnchor(
                isPresented: $isRecording,
                selectedLanguage: selectedLanguage,
                onRecord: saveShortcut
            )
            .allowsHitTesting(false)
        }
    }

    @MainActor
    private func saveShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(shortcut, for: name)
        onChange?(shortcut)
    }
}

/// The event policy is intentionally independent from the popover so the recorder's
/// most important behavior can be regression-tested without driving AppKit UI.
enum ShortcutRecorderInput {
    static func isClearKey(_ keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            && (keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete))
    }

    static func isRecordable(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard !modifierKeyCodes.contains(keyCode) else {
            return false
        }

        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return !modifiers.intersection([.command, .control, .option, .function]).isEmpty
    }

    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command),
        UInt16(kVK_RightCommand),
        UInt16(kVK_Control),
        UInt16(kVK_RightControl),
        UInt16(kVK_Option),
        UInt16(kVK_RightOption),
        UInt16(kVK_Shift),
        UInt16(kVK_RightShift),
        UInt16(kVK_CapsLock),
        UInt16(kVK_Function)
    ]
}

@MainActor
private final class ShortcutRecorderDisplayState: ObservableObject {
    @Published var previewText: String

    init(selectedLanguage: String) {
        previewText = "Press Shortcut".localized(language: selectedLanguage)
    }

    func updateModifierPreview(_ modifierFlags: NSEvent.ModifierFlags, selectedLanguage: String) {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let symbols = modifiers.ks_symbolicRepresentation
        previewText = symbols.isEmpty
            ? "Press Shortcut".localized(language: selectedLanguage)
            : symbols
    }
}

private struct ShortcutRecorderPopoverView: View {
    @ObservedObject var displayState: ShortcutRecorderDisplayState

    var body: some View {
        Text(displayState.previewText)
            .font(.system(.body, design: .monospaced).weight(.medium))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .frame(minWidth: 150, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }
}

private struct ShortcutRecorderPopoverAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let selectedLanguage: String
    let onRecord: (KeyboardShortcuts.Shortcut?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isPresented: isPresented,
            sourceView: nsView,
            selectedLanguage: selectedLanguage,
            onRecord: onRecord,
            onDismiss: { isPresented = false }
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        private var popover: NSPopover?
        private var keyMonitor: Any?
        private var wantsPresentation = false
        private var presentationRetryScheduled = false
        private var selectedLanguage = "system"
        private var onRecord: ((KeyboardShortcuts.Shortcut?) -> Void)?
        private var onDismiss: (() -> Void)?
        private var displayState: ShortcutRecorderDisplayState?

        func update(
            isPresented: Bool,
            sourceView: NSView,
            selectedLanguage: String,
            onRecord: @escaping (KeyboardShortcuts.Shortcut?) -> Void,
            onDismiss: @escaping () -> Void
        ) {
            wantsPresentation = isPresented
            self.selectedLanguage = selectedLanguage
            self.onRecord = onRecord
            self.onDismiss = onDismiss

            if isPresented {
                requestPresentation(from: sourceView)
            } else if popover != nil {
                close()
            }
        }

        func popoverDidClose(_ notification: Notification) {
            popover = nil
            cleanup()
            onDismiss?()
        }

        func close() {
            wantsPresentation = false

            guard let popover else {
                cleanup()
                return
            }

            popover.delegate = nil
            self.popover = nil
            popover.close()
            cleanup()
            onDismiss?()
        }

        private func requestPresentation(from sourceView: NSView) {
            guard wantsPresentation, popover == nil else {
                return
            }

            guard sourceView.window != nil, sourceView.bounds.width > 0, sourceView.bounds.height > 0 else {
                schedulePresentationRetry(from: sourceView)
                return
            }

            present(from: sourceView)
        }

        private func schedulePresentationRetry(from sourceView: NSView) {
            guard !presentationRetryScheduled else {
                return
            }

            presentationRetryScheduled = true
            DispatchQueue.main.async { [weak self, weak sourceView] in
                guard let self, let sourceView else {
                    return
                }

                self.presentationRetryScheduled = false
                self.requestPresentation(from: sourceView)
            }
        }

        private func present(from sourceView: NSView) {
            let displayState = ShortcutRecorderDisplayState(selectedLanguage: selectedLanguage)
            self.displayState = displayState

            let controller = NSHostingController(
                rootView: ShortcutRecorderPopoverView(displayState: displayState)
            )
            controller.view.layoutSubtreeIfNeeded()

            let popover = NSPopover()
            popover.contentViewController = controller
            popover.contentSize = controller.view.fittingSize
            popover.behavior = .transient
            popover.delegate = self
            self.popover = popover

            keyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .flagsChanged]
            ) { [weak self] event in
                guard let self else {
                    return event
                }

                return self.handle(event)
            }

            popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard popover?.isShown == true else {
                return event
            }

            if event.type == .flagsChanged {
                displayState?.updateModifierPreview(
                    event.modifierFlags,
                    selectedLanguage: selectedLanguage
                )
                return event
            }

            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
                close()
                return nil
            }

            if ShortcutRecorderInput.isClearKey(keyCode, modifierFlags: modifiers) {
                commit(nil)
                return nil
            }

            guard
                ShortcutRecorderInput.isRecordable(keyCode: keyCode, modifierFlags: modifiers),
                let shortcut = KeyboardShortcuts.Shortcut(event: event)
            else {
                NSSound.beep()
                return nil
            }

            commit(shortcut)
            return nil
        }

        private func commit(_ shortcut: KeyboardShortcuts.Shortcut?) {
            onRecord?(shortcut)
            close()
        }

        private func cleanup() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }

            keyMonitor = nil
            displayState = nil
            presentationRetryScheduled = false
        }
    }
}

import AppKit
import KeyboardShortcuts
import SwiftUI

struct LocalizedKeyboardShortcutRecorder: NSViewRepresentable {
    typealias NSViewType = KeyboardShortcuts.RecorderCocoa

    let name: KeyboardShortcuts.Name
    let selectedLanguage: String
    let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    init(
        name: KeyboardShortcuts.Name,
        selectedLanguage: String,
        onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil
    ) {
        self.name = name
        self.selectedLanguage = selectedLanguage
        self.onChange = onChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedLanguage: selectedLanguage)
    }

    func makeNSView(context: Context) -> NSViewType {
        let recorder = NSViewType(for: name, onChange: onChange)
        context.coordinator.attach(recorder)
        context.coordinator.update(selectedLanguage: selectedLanguage)
        return recorder
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {
        nsView.shortcutName = name
        context.coordinator.update(selectedLanguage: selectedLanguage)
    }

    final class Coordinator {
        private weak var recorder: NSViewType?
        private var selectedLanguage: String
        private var isRecording = false
        private var recorderActiveObserver: NSObjectProtocol?

        init(selectedLanguage: String) {
            self.selectedLanguage = selectedLanguage
        }

        deinit {
            if let recorderActiveObserver {
                NotificationCenter.default.removeObserver(recorderActiveObserver)
            }
        }

        func attach(_ recorder: NSViewType) {
            self.recorder = recorder
            startObservingIfNeeded()
            applyPlaceholder()
        }

        func update(selectedLanguage: String) {
            self.selectedLanguage = selectedLanguage
            applyPlaceholder()
        }

        private func startObservingIfNeeded() {
            guard recorderActiveObserver == nil else {
                return
            }

            recorderActiveObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                let isActive = notification.userInfo?["isActive"] as? Bool ?? false
                handleRecorderActiveStatusDidChange(isActive: isActive)
            }
        }

        private func handleRecorderActiveStatusDidChange(isActive: Bool) {
            // Do not temporarily clear NSApp.mainMenu key equivalents here. SwiftUI-owned
            // CommandGroup items can retain stale shortcut state on newer macOS releases,
            // which prevents RecorderCocoa from recording or clearing a shortcut.
            isRecording = isActive && recorder?.currentEditor() != nil

            applyPlaceholder()
        }

        private func applyPlaceholder() {
            let key = isRecording ? "Press Shortcut" : "Record Shortcut"
            recorder?.placeholderString = key.localized(language: selectedLanguage)
        }
    }
}

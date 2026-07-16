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
enum ShortcutRecorderRecordingResult: Equatable {
    case accepted
    case rejected(String)
}

struct LocalizedKeyboardShortcutRecorder: View {
    let name: KeyboardShortcuts.Name
    let selectedLanguage: String
    let onRecord: (KeyboardShortcuts.Shortcut?) -> ShortcutRecorderRecordingResult
    let onBeginRecording: (() -> Void)?
    let onEndRecording: (() -> Void)?

    @State private var isRecording = false

    init(
        name: KeyboardShortcuts.Name,
        selectedLanguage: String,
        onRecord: @escaping (KeyboardShortcuts.Shortcut?) -> ShortcutRecorderRecordingResult,
        onBeginRecording: (() -> Void)? = nil,
        onEndRecording: (() -> Void)? = nil
    ) {
        self.name = name
        self.selectedLanguage = selectedLanguage
        self.onRecord = onRecord
        self.onBeginRecording = onBeginRecording
        self.onEndRecording = onEndRecording
    }

    private var shortcut: KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: name)
    }

    private var displayText: String {
        return shortcut.map(ShortcutRecorderDisplay.formattedShortcut)
            ?? "No shortcut".localized(language: selectedLanguage)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording = true
            } label: {
                ShortcutRecorderField(
                    displayText: displayText,
                    isPlaceholder: shortcut == nil,
                    isRecording: isRecording
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Keyboard Shortcut".localized(language: selectedLanguage)))
            .help("Record Shortcut".localized(language: selectedLanguage))

            if shortcut != nil {
                Button {
                    _ = onRecord(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Delete".localized(language: selectedLanguage)))
                .help("Delete".localized(language: selectedLanguage))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .background {
            GeometryReader { proxy in
                ShortcutRecorderPopoverAnchor(
                    isPresented: $isRecording,
                    selectedLanguage: selectedLanguage,
                    onRecord: onRecord,
                    onBeginRecording: onBeginRecording,
                    onEndRecording: onEndRecording
                )
                .frame(width: max(proxy.size.width, 1), height: max(proxy.size.height, 1))
                .allowsHitTesting(false)
            }
        }
    }
}

/// The shared visual treatment for a saved shortcut and its live recording preview.
private struct ShortcutRecorderField: View {
    let displayText: String
    let isPlaceholder: Bool
    let isRecording: Bool
    var minWidth: CGFloat = 126

    var body: some View {
        Text(displayText)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(
                isRecording
                    ? AnyShapeStyle(Color.accentColor)
                    : isPlaceholder
                        ? AnyShapeStyle(.tertiary)
                        : AnyShapeStyle(.primary)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: minWidth, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fieldBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isRecording
                            ? Color.accentColor
                            : fieldBorderColor,
                        lineWidth: isRecording ? 1.5 : 1
                    )
            )
    }

    private var fieldBackgroundColor: Color {
        dynamicColor(light: 0xFFFFFF, dark: 0x1C1D20)
    }

    private var fieldBorderColor: Color {
        dynamicColor(light: 0xDDE1E7, dark: 0x3B3C42)
    }

    private func dynamicColor(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil, dynamicProvider: { appearance in
                let color = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? dark
                    : light
                return NSColor(
                    calibratedRed: CGFloat((color >> 16) & 0xFF) / 255,
                    green: CGFloat((color >> 8) & 0xFF) / 255,
                    blue: CGFloat(color & 0xFF) / 255,
                    alpha: 1
                )
            })
        )
    }
}

/// Formats shortcuts as separate controls, matching the recorder's visual language.
@MainActor
enum ShortcutRecorderDisplay {
    static func formattedShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> String {
        let modifierSymbols = shortcut.modifiers.ks_symbolicRepresentation
        let key = String(shortcut.description.dropFirst(modifierSymbols.count))
        return components(modifiers: modifierSymbols, key: key)
    }

    static func formattedModifierPreview(_ modifiers: NSEvent.ModifierFlags) -> String {
        components(modifiers: modifiers.ks_symbolicRepresentation, key: nil)
    }

    private static func components(modifiers: String, key: String?) -> String {
        var components = modifiers.map(String.init)

        if let key, !key.isEmpty {
            components.append(key)
        }

        return components.joined(separator: " + ")
    }
}

/// The event policy is intentionally independent from the popover so the recorder's
/// most important behavior can be regression-tested without driving AppKit UI.
enum ShortcutRecorderInput {
    static func isRecordable(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard !modifierKeyCodes.contains(keyCode) else {
            return false
        }

        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return !modifiers.intersection([.command, .control, .option, .function]).isEmpty
            || modifierlessFunctionKeyCodes.contains(keyCode)
    }

    static func requiresModifier(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard !modifierKeyCodes.contains(keyCode) else {
            return false
        }

        return modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .control, .option, .function])
            .isEmpty
            && !modifierlessFunctionKeyCodes.contains(keyCode)
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

    private static let modifierlessFunctionKeyCodes: Set<UInt16> = [
        UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
        UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
        UInt16(kVK_F9), UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12)
    ]
}

enum ShortcutRecorderSessionPolicy {
    static let monitoredEventTypes: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]

    static let cancelingWindowNotifications: [Notification.Name] = [
        NSWindow.didResignKeyNotification,
        NSWindow.willCloseNotification
    ]
}

@MainActor
private final class ShortcutRecorderDisplayState: ObservableObject {
    @Published var previewText: String
    @Published private(set) var showEscapeHint = false
    @Published private(set) var rejectionMessage: String?
    @Published private(set) var shakeOffset: CGFloat = 0
    @Published private(set) var isShaking = false

    init(selectedLanguage: String) {
        previewText = "Press Shortcut".localized(language: selectedLanguage)
    }

    func updateModifierPreview(_ modifierFlags: NSEvent.ModifierFlags, selectedLanguage: String) {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let preview = ShortcutRecorderDisplay.formattedModifierPreview(modifiers)
        previewText = preview.isEmpty
            ? "Press Shortcut".localized(language: selectedLanguage)
            : preview
    }

    func reject(message: String? = nil) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            showEscapeHint = true
            if let message {
                rejectionMessage = message
            }
        }

        isShaking = true
        let steps: [(CGFloat, Double)] = [
            (10, 0.00), (-8, 0.06), (7, 0.12), (-5, 0.18), (3, 0.24), (0, 0.30)
        ]

        for (offset, delay) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                withAnimation(.linear(duration: 0.05)) {
                    self?.shakeOffset = offset
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { [weak self] in
            self?.isShaking = false
        }
    }
}

private struct ShortcutRecorderPopoverView: View {
    @ObservedObject var displayState: ShortcutRecorderDisplayState
    let selectedLanguage: String

    private let contentWidth: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            Text(displayState.previewText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 130, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            displayState.isShaking
                                ? Color.red.opacity(0.18)
                                : Color.accentColor.opacity(0.08)
                        )
                )
                .offset(x: displayState.shakeOffset)

            if let rejectionMessage = displayState.rejectionMessage {
                Text(rejectionMessage)
                    .foregroundStyle(.red)
                    .font(.caption2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -6)),
                        removal: .opacity
                    ))
            } else if displayState.showEscapeHint {
                Text("Press ESC to cancel".localized(language: selectedLanguage))
                    .foregroundStyle(.secondary)
                    .font(.caption2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -6)),
                        removal: .opacity
                    ))
            }
        }
        .frame(width: contentWidth)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ShortcutRecorderPopoverAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let selectedLanguage: String
    let onRecord: (KeyboardShortcuts.Shortcut?) -> ShortcutRecorderRecordingResult
    var onBeginRecording: (() -> Void)?
    var onEndRecording: (() -> Void)?

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
            onDismiss: { isPresented = false },
            onBeginRecording: onBeginRecording,
            onEndRecording: onEndRecording
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        private var popover: NSPopover?
        private var eventMonitor: Any?
        private var cancellationObservers: [NSObjectProtocol] = []
        private var isRecordingSessionActive = false
        private var wantsPresentation = false
        private var presentationRetryScheduled = false
        private var selectedLanguage = "system"
        private var onRecord: ((KeyboardShortcuts.Shortcut?) -> ShortcutRecorderRecordingResult)?
        private var onDismiss: (() -> Void)?
        private var onBeginRecording: (() -> Void)?
        private var onEndRecording: (() -> Void)?
        private var displayState: ShortcutRecorderDisplayState?

        func update(
            isPresented: Bool,
            sourceView: NSView,
            selectedLanguage: String,
            onRecord: @escaping (KeyboardShortcuts.Shortcut?) -> ShortcutRecorderRecordingResult,
            onDismiss: @escaping () -> Void,
            onBeginRecording: (() -> Void)?,
            onEndRecording: (() -> Void)?
        ) {
            wantsPresentation = isPresented
            self.selectedLanguage = selectedLanguage
            self.onRecord = onRecord
            self.onDismiss = onDismiss
            self.onBeginRecording = onBeginRecording
            self.onEndRecording = onEndRecording

            if isPresented {
                requestPresentation(from: sourceView)
            } else if popover != nil {
                close()
            }
        }

        func popoverDidClose(_ notification: Notification) {
            guard let closingPopover = notification.object as? NSPopover,
                  closingPopover === popover else {
                return
            }

            popover = nil
            finishSession(closePopover: false)
        }

        func close() {
            finishSession(closePopover: true)
        }

        private func finishSession(closePopover: Bool) {
            wantsPresentation = false

            let dismiss = onDismiss
            let endRecording = onEndRecording
            let wasRecording = isRecordingSessionActive

            if closePopover, let popover {
                popover.delegate = nil
                self.popover = nil
                popover.close()
            }
            cleanup()

            if wasRecording {
                dismiss?()
                endRecording?()
            }
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
            isRecordingSessionActive = true
            onBeginRecording?()

            let controller = NSHostingController(
                rootView: ShortcutRecorderPopoverView(
                    displayState: displayState,
                    selectedLanguage: selectedLanguage
                )
            )
            controller.view.layoutSubtreeIfNeeded()

            let popover = NSPopover()
            popover.contentViewController = controller
            popover.contentSize = controller.view.fittingSize
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
            self.popover = popover

            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: ShortcutRecorderSessionPolicy.monitoredEventTypes
            ) { [weak self] event in
                guard let self else {
                    return event
                }

                return self.handleEvent(event)
            }

            popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
            registerCancellationObservers(for: sourceView.window)
        }

        private func handleEvent(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            case .flagsChanged:
                guard popover?.isShown == true else { return event }
                displayState?.updateModifierPreview(
                    event.modifierFlags,
                    selectedLanguage: selectedLanguage
                )
                return event
            case .keyDown:
                return handleKey(event)
            default:
                return event
            }
        }

        private func handleKey(_ event: NSEvent) -> NSEvent? {
            guard popover?.isShown == true else {
                return event
            }

            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
                close()
                return nil
            }

            if ShortcutRecorderInput.requiresModifier(keyCode: keyCode, modifierFlags: modifiers) {
                reject(
                    message: "Shortcut must include a modifier key.".localized(language: selectedLanguage)
                )
                return nil
            }

            guard
                ShortcutRecorderInput.isRecordable(keyCode: keyCode, modifierFlags: modifiers),
                let shortcut = KeyboardShortcuts.Shortcut(event: event)
            else {
                return nil
            }

            switch onRecord?(shortcut) ?? .accepted {
            case .accepted:
                close()
            case let .rejected(message):
                reject(message: message)
            }
            return nil
        }

        private func reject(message: String) {
            displayState?.reject(message: message)

            // The popover is initially sized before validation feedback exists.
            // Recalculate after SwiftUI applies the new multiline text.
            DispatchQueue.main.async { [weak self] in
                guard
                    let popover = self?.popover,
                    popover.isShown,
                    let contentView = popover.contentViewController?.view
                else {
                    return
                }

                contentView.layoutSubtreeIfNeeded()
                popover.contentSize = contentView.fittingSize
            }
        }

        private func registerCancellationObservers(for window: NSWindow?) {
            let center = NotificationCenter.default

            if let window {
                cancellationObservers.append(contentsOf:
                    ShortcutRecorderSessionPolicy.cancelingWindowNotifications.map { name in
                        center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                self?.close()
                            }
                        }
                    }
                )
            }

            cancellationObservers.append(
                center.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: NSApp,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.close()
                    }
                }
            )
        }

        private func cleanup() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            cancellationObservers.forEach(NotificationCenter.default.removeObserver)

            eventMonitor = nil
            cancellationObservers.removeAll()
            displayState = nil
            isRecordingSessionActive = false
            presentationRetryScheduled = false
            onRecord = nil
            onDismiss = nil
            onBeginRecording = nil
            onEndRecording = nil
        }
    }
}

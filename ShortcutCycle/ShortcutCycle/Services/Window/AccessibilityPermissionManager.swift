import Foundation
import ApplicationServices
import Combine

// MARK: - Accessibility Permission Manager

/// Observable manager that tracks Accessibility permission status.
/// Polls every 1 second after requesting permission until granted.
@MainActor
class AccessibilityPermissionManager: ObservableObject {
    static let shared = AccessibilityPermissionManager()

    @Published private(set) var isGranted: Bool

    private var pollTimer: Timer?

    private init() {
        self.isGranted = AXIsProcessTrusted()
    }

    /// Check current permission status (single check, no polling)
    func checkPermission() {
        isGranted = AXIsProcessTrusted()
    }

    /// Request Accessibility permission and start polling until granted
    func requestPermission() {
        WindowEnumerator.requestAccessibility()
        startPolling()
    }

    /// Start polling for permission status changes
    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.isGranted {
                    self.isGranted = trusted
                }
                if trusted {
                    self.stopPolling()
                }
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

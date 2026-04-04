import AppKit

// MARK: - Shared Test Helpers

/// A testable NSWindow subclass that stubs `isVisible` and `isOnActiveSpace`
/// without depending on actual window-server state.
@MainActor
final class MockWindow: NSWindow {
    private let mockIsVisible: Bool
    private let mockIsOnActiveSpace: Bool

    init(
        identifier: NSUserInterfaceItemIdentifier?,
        isVisible: Bool,
        isOnActiveSpace: Bool
    ) {
        self.mockIsVisible = isVisible
        self.mockIsOnActiveSpace = isOnActiveSpace
        super.init(
            contentRect: .zero,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        self.identifier = identifier
    }

    override var isVisible: Bool {
        mockIsVisible
    }

    override var isOnActiveSpace: Bool {
        mockIsOnActiveSpace
    }
}

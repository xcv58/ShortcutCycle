import AppKit

// MARK: - Shared Test Helpers

/// A testable NSWindow subclass that stubs `isVisible` and `isOnActiveSpace`
/// without depending on actual window-server state.
@MainActor
final class MockWindow: NSWindow {
    private let mockIsVisible: Bool
    private let mockIsOnActiveSpace: Bool
    private let mockIsKeyWindow: Bool
    private let mockIsMainWindow: Bool

    init(
        identifier: NSUserInterfaceItemIdentifier?,
        isVisible: Bool,
        isOnActiveSpace: Bool,
        isKeyWindow: Bool = false,
        isMainWindow: Bool = false
    ) {
        self.mockIsVisible = isVisible
        self.mockIsOnActiveSpace = isOnActiveSpace
        self.mockIsKeyWindow = isKeyWindow
        self.mockIsMainWindow = isMainWindow
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

    override var isKeyWindow: Bool {
        mockIsKeyWindow
    }

    override var isMainWindow: Bool {
        mockIsMainWindow
    }
}

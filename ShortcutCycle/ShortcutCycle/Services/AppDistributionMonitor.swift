import Combine
import Foundation
import StoreKit

// MARK: - App Distribution

    /// The channel through which this copy of ShortcutCycle is running.
enum AppDistributionChannel: Equatable {
    case development
    case sandboxBeta
    case appStore

    var applicationName: String {
        switch self {
        case .development:
            return "ShortcutCycle Dev"
        case .sandboxBeta, .appStore:
            return "ShortcutCycle"
        }
    }

    var titleKey: String? {
        switch self {
        case .development:
            return "Development Build"
        case .sandboxBeta:
            return "Sandbox Beta"
        case .appStore:
            return nil
        }
    }

    var detailKey: String? {
        switch self {
        case .development:
            return "This is a local development build. Its settings are kept separate from the App Store app."
        case .sandboxBeta:
            return "This beta build uses the StoreKit sandbox environment."
        case .appStore:
            return nil
        }
    }

    var symbolName: String? {
        switch self {
        case .development:
            return "hammer.fill"
        case .sandboxBeta:
            return "testtube.2"
        case .appStore:
            return nil
        }
    }

    var usesWarningColor: Bool {
        self == .development
    }

    static func resolve(
        isDebugBuild: Bool,
        storeEnvironment: AppStore.Environment?
    ) -> AppDistributionChannel {
        guard !isDebugBuild else { return .development }
        return storeEnvironment == .sandbox ? .sandboxBeta : .appStore
    }
}

/// Publishes the channel for release archives after StoreKit verifies the app transaction.
/// Debug builds are known locally at compile time and never make a StoreKit request.
@MainActor
final class AppDistributionMonitor: ObservableObject {
    static let shared = AppDistributionMonitor()

    @Published private(set) var channel: AppDistributionChannel

    var shouldShowStatus: Bool {
        #if DEBUG
        return !ScreenshotMode.usesSyntheticControls && channel != .appStore
        #else
        return channel != .appStore
        #endif
    }

    private init() {
        #if DEBUG
        channel = .development
        #else
        channel = .appStore
        Task { [weak self] in
            await self?.refresh()
        }
        #endif
    }

    private func refresh() async {
        guard let result = try? await AppTransaction.shared,
              case .verified(let transaction) = result else {
            return
        }

        channel = AppDistributionChannel.resolve(
            isDebugBuild: false,
            storeEnvironment: transaction.environment
        )
    }
}

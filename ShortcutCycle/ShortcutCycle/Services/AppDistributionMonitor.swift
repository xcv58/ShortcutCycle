import Combine
import Foundation
import StoreKit

// MARK: - App Distribution

/// The channel through which this copy of ShortcutCycle is running.
enum AppDistributionChannel: Equatable {
    case development
    case testFlight
    case appStore

    var applicationName: String {
        switch self {
        case .development:
            return "ShortcutCycle Dev"
        case .testFlight, .appStore:
            return "ShortcutCycle"
        }
    }

    var titleKey: String {
        switch self {
        case .development:
            return "Development Build"
        case .testFlight:
            return "TestFlight Beta"
        case .appStore:
            return ""
        }
    }

    var detailKey: String? {
        switch self {
        case .development:
            return "This is a local development build. Its settings are kept separate from the App Store app."
        case .testFlight:
            return "This beta build was installed with TestFlight."
        case .appStore:
            return nil
        }
    }

    var symbolName: String? {
        switch self {
        case .development:
            return "hammer.fill"
        case .testFlight:
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
        return storeEnvironment == .sandbox ? .testFlight : .appStore
    }
}

/// Publishes the channel for release archives after StoreKit verifies the app transaction.
/// Debug builds are known locally at compile time and never make a StoreKit request.
@MainActor
final class AppDistributionMonitor: ObservableObject {
    @Published private(set) var channel: AppDistributionChannel

    init() {
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

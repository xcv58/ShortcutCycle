import Combine
import Foundation
import Security

// MARK: - App Distribution

    /// The channel through which this copy of ShortcutCycle is running.
enum AppDistributionChannel: Equatable {
    case development
    case testFlightBeta
    case appStore

    var applicationName: String {
        switch self {
        case .development:
            return "ShortcutCycle Dev"
        case .testFlightBeta, .appStore:
            return "ShortcutCycle"
        }
    }

    var titleKey: String? {
        switch self {
        case .development:
            return "Development Build"
        case .testFlightBeta:
            return "TestFlight Beta"
        case .appStore:
            return nil
        }
    }

    var detailKey: String? {
        switch self {
        case .development:
            return "This is a local development build. Its settings are kept separate from the App Store app."
        case .testFlightBeta:
            return "This beta build was installed with TestFlight."
        case .appStore:
            return nil
        }
    }

    var symbolName: String? {
        switch self {
        case .development:
            return "hammer.fill"
        case .testFlightBeta:
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
        signingCertificateSubjects: [String]
    ) -> AppDistributionChannel {
        guard !isDebugBuild else { return .development }
        return signingCertificateSubjects.contains("TestFlight Beta Distribution")
            ? .testFlightBeta
            : .appStore
    }
}

/// Publishes the channel from the app bundle's signing identity.
/// TestFlight macOS builds use the `TestFlight Beta Distribution` signing certificate,
/// while App Store builds remain unbadged.
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
        channel = AppDistributionChannel.resolve(
            isDebugBuild: false,
            signingCertificateSubjects: Self.signingCertificateSubjects()
        )
        #endif
    }

    private static func signingCertificateSubjects() -> [String] {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
        let staticCode else {
            return []
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let certificates = (signingInformation as NSDictionary?)?[kSecCodeInfoCertificates] as? [SecCertificate] else {
            return []
        }

        return certificates.compactMap {
            SecCertificateCopySubjectSummary($0) as String?
        }
    }
}

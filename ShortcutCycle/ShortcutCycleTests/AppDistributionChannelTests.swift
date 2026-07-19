import XCTest
@testable import ShortcutCycle

final class AppDistributionChannelTests: XCTestCase {
    func testDebugBuildIsDevelopmentEvenWithTestFlightSigningCertificate() {
        XCTAssertEqual(
            AppDistributionChannel.resolve(
                isDebugBuild: true,
                signingCertificateSubjects: ["TestFlight Beta Distribution"]
            ),
            .development
        )
    }

    func testTestFlightSigningCertificateIsTestFlightBeta() {
        XCTAssertEqual(
            AppDistributionChannel.resolve(
                isDebugBuild: false,
                signingCertificateSubjects: [
                    "TestFlight Beta Distribution",
                    "Apple Worldwide Developer Relations Certification Authority",
                    "Apple Root CA"
                ]
            ),
            .testFlightBeta
        )
    }

    func testNonTestFlightSigningCertificateIsAppStore() {
        XCTAssertEqual(
            AppDistributionChannel.resolve(
                isDebugBuild: false,
                signingCertificateSubjects: ["Apple Distribution: Jenny Media LLC (5736QK4NZX)"]
            ),
            .appStore
        )
    }

    func testMissingSigningCertificateIsAppStore() {
        XCTAssertEqual(
            AppDistributionChannel.resolve(
                isDebugBuild: false,
                signingCertificateSubjects: []
            ),
            .appStore
        )
    }

    func testAppStoreHasNoDistributionPresentationMetadata() {
        XCTAssertNil(AppDistributionChannel.appStore.titleKey)
        XCTAssertNil(AppDistributionChannel.appStore.detailKey)
        XCTAssertNil(AppDistributionChannel.appStore.symbolName)
    }

    @MainActor
    func testSharedMonitorIsSingleton() {
        let firstMonitor = AppDistributionMonitor.shared
        let secondMonitor = AppDistributionMonitor.shared
        XCTAssertTrue(firstMonitor === secondMonitor)
    }
}

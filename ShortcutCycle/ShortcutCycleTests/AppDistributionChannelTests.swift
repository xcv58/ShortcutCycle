import XCTest
@testable import ShortcutCycle

final class AppDistributionChannelTests: XCTestCase {
    func testDebugBuildIsDevelopmentEvenWithProductionStoreEnvironment() {
        XCTAssertEqual(
            AppDistributionChannel.resolve(
                isDebugBuild: true,
                storeEnvironment: .production
            ),
            .development
        )
    }

    func testSandboxStoreEnvironmentIsSandboxBeta() {
        XCTAssertEqual(
            AppDistributionChannel.resolve(
                isDebugBuild: false,
                storeEnvironment: .sandbox
            ),
            .sandboxBeta
        )
    }

    func testProductionStoreEnvironmentIsAppStore() {
        XCTAssertEqual(
            AppDistributionChannel.resolve(
                isDebugBuild: false,
                storeEnvironment: .production
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

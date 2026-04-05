import XCTest

private struct IntegrationFixture: Codable {
    var exportDate: String
    var groups: [IntegrationFixtureGroup]
    var settings: IntegrationFixtureSettings?
    var shortcuts: [String: IntegrationFixtureShortcut]?
    var version: Int
}

private struct IntegrationFixtureGroup: Codable {
    var apps: [IntegrationFixtureApp]
    var id: String
    var isEnabled: Bool
    var lastModified: String
    var name: String
    var openAppIfNeeded: Bool?
}

private struct IntegrationFixtureApp: Codable {
    var bundleIdentifier: String
    var id: String
    var name: String
    var iconPath: String?
}

private struct IntegrationFixtureSettings: Codable {
    var appTheme: String?
    var selectedLanguage: String?
    var showHUD: Bool
    var showShortcutInHUD: Bool
}

private struct IntegrationFixtureShortcut: Codable {
    var carbonKeyCode: Int
    var carbonModifiers: Int
}

@MainActor
final class ShortcutCycleIntegrationHappyPathTests: ShortcutCycleIntegrationTestCase {
    func testThreeCycleHUDScenario() async throws {
        let session = makeSession(
            artifactSubdirectory: "happy-path",
            fixtureURL: validFixtureURL
        )

        try await session.launch()
        _ = try await session.waitForEvent(.fixtureLoaded)
        try await session.activateFinder()

        let expectedBundleIDs = [
            "com.apple.calculator",
            "com.apple.Chess",
            "com.apple.calculator"
        ]

        var savedFrames: [URL] = []

        for (index, expectedBundleID) in expectedBundleIDs.enumerated() {
            let cycleNumber = index + 1
            session.sendCycle(groupName: "Integration HUD")

            let hudEvent = try await session.waitForEvent(.hudPresented)
            XCTAssertEqual(hudEvent.groupName, "Integration HUD")
            savedFrames.append(try session.captureFrame(label: "cycle\(cycleNumber)-hud"))

            let finalizedEvent = try await session.waitForEvent(.switchFinalized)
            XCTAssertEqual(finalizedEvent.groupName, "Integration HUD")
            XCTAssertEqual(finalizedEvent.activeBundleId, expectedBundleID)
            try await session.waitUntilFrontmostBundleIdentifier(expectedBundleID)
            XCTAssertEqual(session.currentFrontmostBundleIdentifier(), expectedBundleID)
            savedFrames.append(try session.captureFrame(label: "cycle\(cycleNumber)-final"))
        }

        XCTAssertEqual(savedFrames.count, 6)
        for frame in savedFrames {
            XCTAssertTrue(FileManager.default.fileExists(atPath: frame.path))
        }
    }
}

@MainActor
final class ShortcutCycleIntegrationHarnessFailureTests: ShortcutCycleIntegrationTestCase {
    func testMissingFixtureEmitsClearErrorEvent() async throws {
        let missingFixtureURL = runRootURL.appendingPathComponent("missing-fixture.json", isDirectory: false)
        let session = makeSession(
            artifactSubdirectory: "failure-missing-fixture",
            fixtureURL: missingFixtureURL
        )

        try await session.launch()
        let errorEvent = try await session.waitForEvent(.error, failOnError: false)

        XCTAssertEqual(errorEvent.groupName, "")
        XCTAssertTrue(errorEvent.message?.contains("Fixture file not found") == true)
    }

    func testMissingTargetAppEmitsClearErrorEvent() async throws {
        let brokenFixtureURL = try makeFixtureWithMissingTargetApp(
            destinationURL: runRootURL.appendingPathComponent("missing-target-app.json", isDirectory: false)
        )
        let session = makeSession(
            artifactSubdirectory: "failure-missing-target-app",
            fixtureURL: brokenFixtureURL
        )

        try await session.launch()
        let errorEvent = try await session.waitForEvent(.error, failOnError: false)

        XCTAssertEqual(errorEvent.groupName, "Integration HUD")
        XCTAssertTrue(errorEvent.message?.contains("Fixture references a missing target app") == true)
        XCTAssertTrue(errorEvent.message?.contains("com.apple.ShortcutCycleIntegration.MissingApp") == true)
    }

    private func makeFixtureWithMissingTargetApp(destinationURL: URL) throws -> URL {
        let data = try Data(contentsOf: validFixtureURL)

        let decoder = JSONDecoder()
        let export = try decoder.decode(IntegrationFixture.self, from: data)

        var groups = export.groups
        var brokenGroup = try XCTUnwrap(groups.first)
        let firstApp = try XCTUnwrap(brokenGroup.apps.first)
        brokenGroup.apps[0] = IntegrationFixtureApp(
            bundleIdentifier: "com.apple.ShortcutCycleIntegration.MissingApp",
            id: firstApp.id,
            name: "Missing App",
            iconPath: firstApp.iconPath
        )
        groups[0] = brokenGroup

        let rewrittenExport = IntegrationFixture(
            exportDate: export.exportDate,
            groups: groups,
            settings: export.settings,
            shortcuts: export.shortcuts,
            version: export.version
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let directoryURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try encoder.encode(rewrittenExport).write(to: destinationURL, options: .atomic)
        return destinationURL
    }
}

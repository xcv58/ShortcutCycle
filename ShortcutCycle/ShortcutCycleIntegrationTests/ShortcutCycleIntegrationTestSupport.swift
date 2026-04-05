import AppKit
import CoreGraphics
import XCTest

enum ShortcutCycleIntegrationEventName: String, Codable {
    case fixtureLoaded
    case hudPresented
    case switchFinalized
    case error
}

enum ShortcutCycleIntegrationCommandName: String, Codable {
    case cycle
}

enum ShortcutCycleIntegrationNotification {
    static func commandName(runId: String) -> Notification.Name {
        Notification.Name("com.xcv58.ShortcutCycle.Integration.command.\(runId)")
    }

    static func eventName(runId: String) -> Notification.Name {
        Notification.Name("com.xcv58.ShortcutCycle.Integration.event.\(runId)")
    }
}

enum ShortcutCycleIntegrationUserInfoKey: String {
    case activeBundleId
    case command
    case commandId
    case event
    case eventId
    case groupName
    case message
    case runId
    case timestamp
}

struct ShortcutCycleIntegrationCommand: Codable {
    let commandId: String
    let runId: String
    let command: ShortcutCycleIntegrationCommandName
    let groupName: String

    init(
        commandId: String = UUID().uuidString,
        runId: String,
        command: ShortcutCycleIntegrationCommandName,
        groupName: String
    ) {
        self.commandId = commandId
        self.runId = runId
        self.command = command
        self.groupName = groupName
    }

    var userInfo: [String: String] {
        [
            ShortcutCycleIntegrationUserInfoKey.commandId.rawValue: commandId,
            ShortcutCycleIntegrationUserInfoKey.runId.rawValue: runId,
            ShortcutCycleIntegrationUserInfoKey.command.rawValue: command.rawValue,
            ShortcutCycleIntegrationUserInfoKey.groupName.rawValue: groupName
        ]
    }
}

struct ShortcutCycleIntegrationEvent: Codable, Equatable {
    let eventId: String
    let event: ShortcutCycleIntegrationEventName
    let runId: String
    let groupName: String
    let activeBundleId: String
    let timestamp: String
    let message: String?

    init?(userInfo: [AnyHashable: Any]?) {
        guard let eventId = userInfo?[ShortcutCycleIntegrationUserInfoKey.eventId.rawValue] as? String,
              let eventRawValue = userInfo?[ShortcutCycleIntegrationUserInfoKey.event.rawValue] as? String,
              let event = ShortcutCycleIntegrationEventName(rawValue: eventRawValue),
              let runId = userInfo?[ShortcutCycleIntegrationUserInfoKey.runId.rawValue] as? String,
              let groupName = userInfo?[ShortcutCycleIntegrationUserInfoKey.groupName.rawValue] as? String,
              let activeBundleId = userInfo?[ShortcutCycleIntegrationUserInfoKey.activeBundleId.rawValue] as? String,
              let timestamp = userInfo?[ShortcutCycleIntegrationUserInfoKey.timestamp.rawValue] as? String else {
            return nil
        }

        self.eventId = eventId
        self.event = event
        self.runId = runId
        self.groupName = groupName
        self.activeBundleId = activeBundleId
        self.timestamp = timestamp
        self.message = userInfo?[ShortcutCycleIntegrationUserInfoKey.message.rawValue] as? String
    }
}

@MainActor
final class ShortcutCycleIntegrationSession {
    private let fileManager = FileManager.default
    private let distributedCenter = DistributedNotificationCenter.default()
    private let appURL: URL
    private let fixtureURL: URL
    private let artifactsURL: URL
    private let appBundleIdentifier: String

    private var observer: NSObjectProtocol?
    private var observedEventIDs = Set<String>()
    private var bufferedEvents: [ShortcutCycleIntegrationEvent] = []

    private(set) var launchedApp: NSRunningApplication?
    private(set) var frameIndex = 0

    let runId = UUID().uuidString

    init(
        appURL: URL,
        fixtureURL: URL,
        artifactsURL: URL,
        appBundleIdentifier: String
    ) {
        self.appURL = appURL
        self.fixtureURL = fixtureURL
        self.artifactsURL = artifactsURL
        self.appBundleIdentifier = appBundleIdentifier
    }

    var framesDirectoryURL: URL {
        artifactsURL.appendingPathComponent("frames", isDirectory: true)
    }

    var harnessDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(appBundleIdentifier)/Data/Library/Application Support/ShortcutCycle/IntegrationHarness/\(runId)", isDirectory: true)
    }

    var launchFixtureURL: URL {
        harnessDirectoryURL.appendingPathComponent("fixture.json", isDirectory: false)
    }

    var commandLogURL: URL {
        harnessDirectoryURL.appendingPathComponent("commands.ndjson", isDirectory: false)
    }

    var eventLogURL: URL {
        harnessDirectoryURL.appendingPathComponent("events.ndjson", isDirectory: false)
    }

    func launch() async throws {
        try resetArtifactsDirectory()
        try stageLaunchInputs()
        startObservingEvents()
        await terminateRunningIntegrationApps()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        if #available(macOS 13.0, *) {
            configuration.createsNewApplicationInstance = true
        }
        configuration.environment = [
            "SHORTCUTCYCLE_TEST_MODE": "1",
            "SHORTCUTCYCLE_TEST_RUN_ID": runId,
            "SHORTCUTCYCLE_TEST_FIXTURE_PATH": launchFixtureURL.path,
            "SHORTCUTCYCLE_TEST_ARTIFACTS_DIR": harnessDirectoryURL.path
        ]
        configuration.arguments = [
            "--SHORTCUTCYCLE_TEST_MODE=1",
            "--SHORTCUTCYCLE_TEST_RUN_ID=\(runId)",
            "--SHORTCUTCYCLE_TEST_FIXTURE_PATH=\(launchFixtureURL.path)",
            "--SHORTCUTCYCLE_TEST_ARTIFACTS_DIR=\(harnessDirectoryURL.path)"
        ]

        launchedApp = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let app else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "ShortcutCycleIntegration",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "App launch completed without returning a running application instance."]
                        )
                    )
                    return
                }

                continuation.resume(returning: app)
            }
        }
    }

    func terminate() async {
        if let observer {
            distributedCenter.removeObserver(observer)
            self.observer = nil
        }

        await terminateRunningIntegrationApps()
    }

    func sendCycle(groupName: String) {
        let command = ShortcutCycleIntegrationCommand(
            runId: runId,
            command: .cycle,
            groupName: groupName
        )

        distributedCenter.postNotificationName(
            ShortcutCycleIntegrationNotification.commandName(runId: runId),
            object: nil,
            userInfo: command.userInfo,
            deliverImmediately: true
        )

        appendCommandToLog(command)
    }

    func waitForEvent(
        _ expectedEvent: ShortcutCycleIntegrationEventName,
        timeout: TimeInterval = 5.0,
        failOnError: Bool = true
    ) async throws -> ShortcutCycleIntegrationEvent {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            loadEventsFromLogIfNeeded()

            if let event = dequeueEvent(expectedEvent: expectedEvent, failOnError: failOnError) {
                if failOnError, event.event == .error {
                    throw NSError(
                        domain: "ShortcutCycleIntegration",
                        code: 6,
                        userInfo: [NSLocalizedDescriptionKey: event.message ?? "Integration harness emitted an unspecified error."]
                    )
                }
                return event
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        throw NSError(
            domain: "ShortcutCycleIntegration",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(expectedEvent.rawValue)"]
        )
    }

    func captureFrame(label: String) throws -> URL {
        try fileManager.createDirectory(at: framesDirectoryURL, withIntermediateDirectories: true)

        let displayID = preferredCaptureDisplayID(for: label)

        guard let image = CGDisplayCreateImage(displayID) else {
            throw NSError(
                domain: "ShortcutCycleIntegration",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Unable to capture the selected display. Screen Recording permission may be required."]
            )
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "ShortcutCycleIntegration",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode screenshot as PNG."]
            )
        }

        frameIndex += 1
        let fileName = String(format: "frame-%04d-%@.png", frameIndex, sanitize(label))
        let destinationURL = framesDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
        try pngData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private func preferredCaptureDisplayID(for label: String) -> CGDirectDisplayID {
        let lowercasedLabel = label.lowercased()

        if lowercasedLabel.contains("hud"),
           let launchedApp,
           let displayID = displayIDForLargestVisibleWindow(ownerPID: launchedApp.processIdentifier) {
            return displayID
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.bundleIdentifier != appBundleIdentifier,
           let displayID = displayIDForLargestVisibleWindow(ownerPID: frontmostApplication.processIdentifier) {
            return displayID
        }

        if let launchedApp,
           let displayID = displayIDForLargestVisibleWindow(ownerPID: launchedApp.processIdentifier) {
            return displayID
        }

        return fallbackCaptureDisplayID()
    }

    private func displayIDForLargestVisibleWindow(ownerPID: pid_t) -> CGDirectDisplayID? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let candidateBounds = windowList
            .filter { window in
                guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                      pid == ownerPID else {
                    return false
                }

                let isOnscreen = (window[kCGWindowIsOnscreen as String] as? Int) ?? 1
                let alpha = (window[kCGWindowAlpha as String] as? Double) ?? 1
                return isOnscreen == 1 && alpha > 0
            }
            .compactMap(windowBounds(from:))
            .filter { bounds in
                bounds.width >= 80 && bounds.height >= 80
            }
            .max { lhs, rhs in
                lhs.width * lhs.height < rhs.width * rhs.height
            }

        guard let candidateBounds else {
            return nil
        }

        return displayIDContainingMost(of: candidateBounds)
    }

    private func displayIDContainingMost(of bounds: CGRect) -> CGDirectDisplayID? {
        let displays = activeDisplayIDs()
        guard !displays.isEmpty else {
            return nil
        }

        let bestMatch = displays.max { lhs, rhs in
            intersectionArea(between: bounds, and: CGDisplayBounds(lhs)) <
                intersectionArea(between: bounds, and: CGDisplayBounds(rhs))
        }

        if let bestMatch,
           intersectionArea(between: bounds, and: CGDisplayBounds(bestMatch)) > 0 {
            return bestMatch
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return displays.first(where: { CGDisplayBounds($0).contains(center) })
    }

    private func fallbackCaptureDisplayID() -> CGDirectDisplayID {
        if let primaryScreenID = displayID(for: NSScreen.screens.first),
           CGDisplayIsBuiltin(primaryScreenID) == 0 {
            return primaryScreenID
        }

        if let mainScreenID = displayID(for: NSScreen.main),
           CGDisplayIsBuiltin(mainScreenID) == 0 {
            return mainScreenID
        }

        if let externalDisplayID = activeDisplayIDs().first(where: { CGDisplayIsBuiltin($0) == 0 }) {
            return externalDisplayID
        }

        return displayID(for: NSScreen.main) ??
            displayID(for: NSScreen.screens.first) ??
            CGMainDisplayID()
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return []
        }

        var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
            return []
        }

        return Array(displayIDs.prefix(Int(displayCount)))
    }

    private func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private func windowBounds(from window: [String: Any]) -> CGRect? {
        guard let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }

        var bounds = CGRect.null
        guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds) else {
            return nil
        }

        return bounds
    }

    private func intersectionArea(between lhs: CGRect, and rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    func activateFinder() async throws {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            throw NSError(
                domain: "ShortcutCycleIntegration",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Finder is not available for neutral-state activation."]
            )
        }

        if #available(macOS 14.0, *) {
            _ = finder.activate(from: .current, options: [.activateAllWindows])
        } else {
            _ = finder.activate(options: [.activateAllWindows])
        }
        try await waitUntil(
            description: "Finder to become frontmost",
            timeout: 2.0
        ) { [weak self] in
            self?.currentFrontmostBundleIdentifier() == "com.apple.finder"
        }
    }

    func currentFrontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func waitUntilFrontmostBundleIdentifier(
        _ bundleIdentifier: String,
        timeout: TimeInterval = 3.0
    ) async throws {
        try await waitUntil(
            description: "\(bundleIdentifier) to become frontmost",
            timeout: timeout
        ) { [weak self] in
            self?.currentFrontmostBundleIdentifier() == bundleIdentifier
        }
    }

    private func startObservingEvents() {
        guard observer == nil else { return }

        observer = distributedCenter.addObserver(
            forName: ShortcutCycleIntegrationNotification.eventName(runId: runId),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = ShortcutCycleIntegrationEvent(userInfo: notification.userInfo) else {
                return
            }

            Task { @MainActor [weak self] in
                self?.appendEvent(event)
            }
        }
    }

    private func appendEvent(_ event: ShortcutCycleIntegrationEvent) {
        guard observedEventIDs.insert(event.eventId).inserted else { return }
        bufferedEvents.append(event)
    }

    private func loadEventsFromLogIfNeeded() {
        guard let data = try? Data(contentsOf: eventLogURL),
              let contents = String(data: data, encoding: .utf8),
              !contents.isEmpty else {
            return
        }

        let decoder = JSONDecoder()
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let lineData = line.data(using: .utf8),
                  let event = try? decoder.decode(ShortcutCycleIntegrationEvent.self, from: lineData) else {
                continue
            }
            appendEvent(event)
        }
    }

    private func dequeueEvent(
        expectedEvent: ShortcutCycleIntegrationEventName,
        failOnError: Bool
    ) -> ShortcutCycleIntegrationEvent? {
        guard let index = bufferedEvents.firstIndex(where: {
            $0.event == expectedEvent || (failOnError && $0.event == .error)
        }) else {
            return nil
        }

        let event = bufferedEvents.remove(at: index)
        return event
    }

    private func waitUntil(
        description: String,
        timeout: TimeInterval,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        throw NSError(
            domain: "ShortcutCycleIntegration",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(description)."]
        )
    }

    private func terminateRunningIntegrationApps() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: appBundleIdentifier)
        guard !runningApps.isEmpty else { return }

        for app in runningApps {
            app.terminate()
        }

        let deadline = Date().addingTimeInterval(5.0)
        while Date() < deadline {
            let activeApps = NSRunningApplication.runningApplications(withBundleIdentifier: appBundleIdentifier)
            if activeApps.isEmpty {
                launchedApp = nil
                return
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: appBundleIdentifier) {
            app.forceTerminate()
        }
        launchedApp = nil
    }

    private func resetArtifactsDirectory() throws {
        if fileManager.fileExists(atPath: artifactsURL.path) {
            try fileManager.removeItem(at: artifactsURL)
        }
        try fileManager.createDirectory(at: artifactsURL, withIntermediateDirectories: true)
    }

    private func stageLaunchInputs() throws {
        if fileManager.fileExists(atPath: harnessDirectoryURL.path) {
            try fileManager.removeItem(at: harnessDirectoryURL)
        }
        try fileManager.createDirectory(at: harnessDirectoryURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: fixtureURL.path) {
            try fileManager.copyItem(at: fixtureURL, to: launchFixtureURL)
        }
    }

    private func appendCommandToLog(_ command: ShortcutCycleIntegrationCommand) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(command) else {
            return
        }

        if !fileManager.fileExists(atPath: commandLogURL.path) {
            fileManager.createFile(atPath: commandLogURL.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: commandLogURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        } catch {
            XCTFail("Failed to append integration command log: \(error.localizedDescription)")
        }
    }

    private func sanitize(_ label: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let scalars = label.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

@MainActor
class ShortcutCycleIntegrationTestCase: XCTestCase {
    private struct RuntimeContext {
        let appURL: URL
        let validFixtureURL: URL
        let runRootURL: URL
        let appBundleIdentifier: String
    }

    private static let sourceFileURL = URL(fileURLWithPath: #filePath)
    private static let projectRootURL = sourceFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let repoRootURL = projectRootURL.deletingLastPathComponent()
    private static let contextFileURL = repoRootURL
        .appendingPathComponent(".artifacts/xcode-integration/integration-context.env", isDirectory: false)

    private(set) var appURL: URL!
    private(set) var validFixtureURL: URL!
    private(set) var runRootURL: URL!
    private(set) var appBundleIdentifier: String!

    private var sessions: [ShortcutCycleIntegrationSession] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        let runtimeContext = try resolveRuntimeContext()
        appURL = runtimeContext.appURL
        validFixtureURL = runtimeContext.validFixtureURL
        runRootURL = runtimeContext.runRootURL
        appBundleIdentifier = runtimeContext.appBundleIdentifier
    }

    override func tearDown() async throws {
        for session in sessions.reversed() {
            await session.terminate()
        }
        sessions.removeAll()
        try await super.tearDown()
    }

    func makeSession(
        artifactSubdirectory: String,
        fixtureURL: URL
    ) -> ShortcutCycleIntegrationSession {
        let session = ShortcutCycleIntegrationSession(
            appURL: appURL,
            fixtureURL: fixtureURL,
            artifactsURL: runRootURL.appendingPathComponent(artifactSubdirectory, isDirectory: true),
            appBundleIdentifier: appBundleIdentifier
        )
        sessions.append(session)
        return session
    }

    private func resolveRuntimeContext() throws -> RuntimeContext {
        let environment = ProcessInfo.processInfo.environment
        let fileContext = loadContextFile()
        let testBundleProductsURL = Bundle(for: type(of: self)).bundleURL.deletingLastPathComponent()

        let defaultAppURL = testBundleProductsURL.appendingPathComponent("ShortcutCycle.app", isDirectory: true)
        let defaultFixtureURL = Self.projectRootURL
            .appendingPathComponent("ShortcutCycleIntegrationFixtures/IntegrationHUD.settings.json", isDirectory: false)
        let defaultRunRootURL = Self.repoRootURL
            .appendingPathComponent(".artifacts/integration/fallback", isDirectory: true)

        func contextValue(_ key: String) -> String? {
            environment[key] ?? fileContext[key]
        }

        let appURL = URL(
            fileURLWithPath: contextValue("SHORTCUTCYCLE_INTEGRATION_APP_PATH") ?? defaultAppURL.path,
            isDirectory: true
        )
        let validFixtureURL = URL(
            fileURLWithPath: contextValue("SHORTCUTCYCLE_INTEGRATION_VALID_FIXTURE_PATH") ?? defaultFixtureURL.path,
            isDirectory: false
        )
        let runRootURL = URL(
            fileURLWithPath: contextValue("SHORTCUTCYCLE_INTEGRATION_RUN_ROOT") ?? defaultRunRootURL.path,
            isDirectory: true
        )
        let appBundleIdentifier = contextValue("SHORTCUTCYCLE_INTEGRATION_APP_BUNDLE_ID") ?? "com.xcv58.ShortcutCycle.Integration"

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw NSError(
                domain: "ShortcutCycleIntegration",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Expected integration app at \(appURL.path)."]
            )
        }

        guard FileManager.default.fileExists(atPath: validFixtureURL.path) else {
            throw NSError(
                domain: "ShortcutCycleIntegration",
                code: 9,
                userInfo: [NSLocalizedDescriptionKey: "Expected integration fixture at \(validFixtureURL.path)."]
            )
        }

        return RuntimeContext(
            appURL: appURL,
            validFixtureURL: validFixtureURL,
            runRootURL: runRootURL,
            appBundleIdentifier: appBundleIdentifier
        )
    }

    private func loadContextFile() -> [String: String] {
        guard let contents = try? String(contentsOf: Self.contextFileURL, encoding: .utf8) else {
            return [:]
        }

        var values: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let separatorIndex = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separatorIndex])
            let valueStart = line.index(after: separatorIndex)
            let value = String(line[valueStart...])
            values[key] = value
        }
        return values
    }
}

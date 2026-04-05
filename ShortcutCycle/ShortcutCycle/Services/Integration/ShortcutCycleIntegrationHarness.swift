import AppKit
import Foundation
#if canImport(ShortcutCycleCore)
import ShortcutCycleCore
#endif

enum ShortcutCycleIntegrationCommandName: String, Codable {
    case cycle
}

enum ShortcutCycleIntegrationEventName: String, Codable {
    case fixtureLoaded
    case hudPresented
    case switchFinalized
    case error
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

struct ShortcutCycleIntegrationConfiguration {
    private static let testModeFlag = "SHORTCUTCYCLE_TEST_MODE"
    private static let runIDFlag = "SHORTCUTCYCLE_TEST_RUN_ID"
    private static let fixtureFlag = "SHORTCUTCYCLE_TEST_FIXTURE_PATH"
    private static let artifactsFlag = "SHORTCUTCYCLE_TEST_ARTIFACTS_DIR"

    let runId: String
    let fixtureURL: URL
    let artifactsDirectoryURL: URL

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> ShortcutCycleIntegrationConfiguration? {
        let argumentValues = parseArguments(arguments)

        func value(for key: String) -> String? {
            environment[key] ?? argumentValues[key]
        }

        guard value(for: testModeFlag) == "1",
              let runId = value(for: runIDFlag),
              !runId.isEmpty,
              let fixturePath = value(for: fixtureFlag),
              !fixturePath.isEmpty,
              let artifactsPath = value(for: artifactsFlag),
              !artifactsPath.isEmpty else {
            return nil
        }

        return ShortcutCycleIntegrationConfiguration(
            runId: runId,
            fixtureURL: URL(fileURLWithPath: fixturePath),
            artifactsDirectoryURL: URL(fileURLWithPath: artifactsPath, isDirectory: true)
        )
    }

    private static func parseArguments(_ arguments: [String]) -> [String: String] {
        var values: [String: String] = [:]

        for argument in arguments {
            guard argument.hasPrefix("--"),
                  let separatorIndex = argument.firstIndex(of: "=") else {
                continue
            }

            let key = String(argument[argument.index(argument.startIndex, offsetBy: 2)..<separatorIndex])
            let valueStart = argument.index(after: separatorIndex)
            let value = String(argument[valueStart...])
            values[key] = value
        }

        return values
    }
}

struct ShortcutCycleIntegrationTimings {
    let hudShowDelay: TimeInterval
    let loopStartDelay: TimeInterval
    let repeatLoopInterval: TimeInterval
    let autoHideDelay: TimeInterval
    let modifierReleaseGraceDelay: TimeInterval

    static let standard = ShortcutCycleIntegrationTimings(
        hudShowDelay: 0.2,
        loopStartDelay: 0.2,
        repeatLoopInterval: 0.125,
        autoHideDelay: 1.0,
        modifierReleaseGraceDelay: 0.05
    )

    static let integration = ShortcutCycleIntegrationTimings(
        hudShowDelay: 0.05,
        loopStartDelay: 0.05,
        repeatLoopInterval: 0.08,
        autoHideDelay: 0.25,
        modifierReleaseGraceDelay: 0.18
    )
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

    init?(userInfo: [AnyHashable: Any]?) {
        guard let commandId = userInfo?[ShortcutCycleIntegrationUserInfoKey.commandId.rawValue] as? String,
              let runId = userInfo?[ShortcutCycleIntegrationUserInfoKey.runId.rawValue] as? String,
              let commandRawValue = userInfo?[ShortcutCycleIntegrationUserInfoKey.command.rawValue] as? String,
              let command = ShortcutCycleIntegrationCommandName(rawValue: commandRawValue),
              let groupName = userInfo?[ShortcutCycleIntegrationUserInfoKey.groupName.rawValue] as? String else {
            return nil
        }

        self.init(commandId: commandId, runId: runId, command: command, groupName: groupName)
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

    init(
        eventId: String = UUID().uuidString,
        event: ShortcutCycleIntegrationEventName,
        runId: String,
        groupName: String,
        activeBundleId: String,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        message: String? = nil
    ) {
        self.eventId = eventId
        self.event = event
        self.runId = runId
        self.groupName = groupName
        self.activeBundleId = activeBundleId
        self.timestamp = timestamp
        self.message = message
    }

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

        self.init(
            eventId: eventId,
            event: event,
            runId: runId,
            groupName: groupName,
            activeBundleId: activeBundleId,
            timestamp: timestamp,
            message: userInfo?[ShortcutCycleIntegrationUserInfoKey.message.rawValue] as? String
        )
    }

    var userInfo: [String: String] {
        var userInfo: [String: String] = [
            ShortcutCycleIntegrationUserInfoKey.eventId.rawValue: eventId,
            ShortcutCycleIntegrationUserInfoKey.event.rawValue: event.rawValue,
            ShortcutCycleIntegrationUserInfoKey.runId.rawValue: runId,
            ShortcutCycleIntegrationUserInfoKey.groupName.rawValue: groupName,
            ShortcutCycleIntegrationUserInfoKey.activeBundleId.rawValue: activeBundleId,
            ShortcutCycleIntegrationUserInfoKey.timestamp.rawValue: timestamp
        ]

        if let message {
            userInfo[ShortcutCycleIntegrationUserInfoKey.message.rawValue] = message
        }

        return userInfo
    }
}

@MainActor
final class ShortcutCycleIntegrationHarness {
    static let shared = ShortcutCycleIntegrationHarness()

    private let distributedCenter = DistributedNotificationCenter.default()
    private let fileManager = FileManager.default
    private let commandLogFileName = "commands.ndjson"
    private let eventLogFileName = "events.ndjson"

    private var observer: NSObjectProtocol?
    private var commandPollingTask: Task<Void, Never>?
    private(set) var configuration = ShortcutCycleIntegrationConfiguration.load()
    private(set) var isFixtureReady = false
    private var hasStarted = false
    private var handledCommandIDs = Set<String>()

    private(set) var currentGroupName = ""

    var isActive: Bool {
        configuration != nil
    }

    var timings: ShortcutCycleIntegrationTimings {
        isActive ? .integration : .standard
    }

    private init() {}

    func startIfNeeded() {
        guard let configuration, !hasStarted else { return }
        hasStarted = true

        prepareArtifactsDirectory(at: configuration.artifactsDirectoryURL)
        registerDistributedCommandObserver(runId: configuration.runId)
        startPollingCommandLog(using: configuration)
        bootstrapFixture(using: configuration)
    }

    func recordCycleRequest(groupName: String) {
        guard isActive else { return }
        currentGroupName = groupName
    }

    func recordHUDPresented(activeAppId: String, items: [HUDAppItem]) {
        guard isActive, isFixtureReady else { return }
        emit(
            event: .hudPresented,
            groupName: currentGroupName,
            activeBundleId: resolvedBundleId(for: activeAppId, items: items)
        )
    }

    func recordSwitchFinalized(targetAppId: String, items: [HUDAppItem]) {
        guard isActive, isFixtureReady else { return }

        let groupName = currentGroupName
        let targetBundleId = resolvedBundleId(for: targetAppId, items: items)

        Task { @MainActor [weak self] in
            await self?.emitSwitchFinalized(groupName: groupName, targetBundleId: targetBundleId)
        }
    }

    private func bootstrapFixture(using configuration: ShortcutCycleIntegrationConfiguration) {
        guard fileManager.fileExists(atPath: configuration.fixtureURL.path) else {
            emitError(
                "Fixture file not found at \(configuration.fixtureURL.path)",
                groupName: "",
                activeBundleId: currentFrontmostBundleId() ?? ""
            )
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: configuration.fixtureURL)
        } catch {
            emitError(
                "Failed to read fixture file at \(configuration.fixtureURL.path): \(error.localizedDescription)",
                groupName: "",
                activeBundleId: currentFrontmostBundleId() ?? ""
            )
            return
        }

        switch SettingsExport.validate(data: data) {
        case .failure(let error):
            emitError(
                "Failed to decode fixture file at \(configuration.fixtureURL.path): \(error.localizedDescription)",
                groupName: "",
                activeBundleId: currentFrontmostBundleId() ?? ""
            )
        case .success(let payload):
            if let missingBundleId = firstMissingTargetApp(in: payload.groups) {
                emitError(
                    "Fixture references a missing target app: \(missingBundleId)",
                    groupName: payload.groups.first?.name ?? "",
                    activeBundleId: currentFrontmostBundleId() ?? ""
                )
                return
            }

            GroupStore.shared.applyImport(payload)
            ShortcutManager.shared.registerAllShortcuts()

            isFixtureReady = true
            currentGroupName = payload.groups.first?.name ?? ""

            emit(
                event: .fixtureLoaded,
                groupName: currentGroupName,
                activeBundleId: currentFrontmostBundleId() ?? ""
            )
        }
    }

    private func registerDistributedCommandObserver(runId: String) {
        observer = distributedCenter.addObserver(
            forName: ShortcutCycleIntegrationNotification.commandName(runId: runId),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleDistributedCommand(notification)
            }
        }
    }

    private func handleDistributedCommand(_ notification: Notification) {
        guard let configuration,
              let command = ShortcutCycleIntegrationCommand(userInfo: notification.userInfo),
              command.runId == configuration.runId else {
            return
        }

        handleIncomingCommand(command)
    }

    private func handleIncomingCommand(_ command: ShortcutCycleIntegrationCommand) {
        guard handledCommandIDs.insert(command.commandId).inserted else {
            return
        }

        switch command.command {
        case .cycle:
            handleCycle(groupName: command.groupName)
        }
    }

    private func handleCycle(groupName: String) {
        guard isFixtureReady else {
            emitError(
                "Fixture has not finished loading yet",
                groupName: groupName,
                activeBundleId: currentFrontmostBundleId() ?? ""
            )
            return
        }

        let store = GroupStore.shared
        guard let group = store.groups.first(where: { $0.name == groupName }) else {
            emitError(
                "Group not found: \(groupName)",
                groupName: groupName,
                activeBundleId: currentFrontmostBundleId() ?? ""
            )
            return
        }

        guard group.isEnabled else {
            emitError(
                "Group is disabled: \(groupName)",
                groupName: groupName,
                activeBundleId: currentFrontmostBundleId() ?? ""
            )
            return
        }

        if let missingBundleId = firstMissingTargetApp(in: [group]) {
            emitError(
                "Target app is not installed: \(missingBundleId)",
                groupName: groupName,
                activeBundleId: currentFrontmostBundleId() ?? ""
            )
            return
        }

        recordCycleRequest(groupName: groupName)
        store.selectedGroupId = group.id
        AppSwitcher.shared.handleShortcut(for: group, store: store)
    }

    private func emitSwitchFinalized(groupName: String, targetBundleId: String) async {
        let timeout = Date().addingTimeInterval(3.0)

        while Date() < timeout {
            if currentFrontmostBundleId() == targetBundleId {
                emit(
                    event: .switchFinalized,
                    groupName: groupName,
                    activeBundleId: targetBundleId
                )
                return
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        emitError(
            "Timed out waiting for frontmost app to become \(targetBundleId)",
            groupName: groupName,
            activeBundleId: currentFrontmostBundleId() ?? targetBundleId
        )
    }

    private func emit(
        event: ShortcutCycleIntegrationEventName,
        groupName: String,
        activeBundleId: String,
        message: String? = nil
    ) {
        guard let configuration else { return }

        let integrationEvent = ShortcutCycleIntegrationEvent(
            event: event,
            runId: configuration.runId,
            groupName: groupName,
            activeBundleId: activeBundleId,
            message: message
        )

        appendToEventLog(integrationEvent)
        distributedCenter.postNotificationName(
            ShortcutCycleIntegrationNotification.eventName(runId: configuration.runId),
            object: nil,
            userInfo: integrationEvent.userInfo,
            deliverImmediately: true
        )
    }

    private func emitError(
        _ message: String,
        groupName: String,
        activeBundleId: String
    ) {
        emit(
            event: .error,
            groupName: groupName,
            activeBundleId: activeBundleId,
            message: message
        )
    }

    private func firstMissingTargetApp(in groups: [AppGroup]) -> String? {
        groups
            .flatMap(\.apps)
            .map(\.bundleIdentifier)
            .first(where: {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) == nil
            })
    }

    private func resolvedBundleId(for appId: String, items: [HUDAppItem]) -> String {
        if let match = items.first(where: { $0.id == appId || $0.bundleId == appId }) {
            return match.bundleId
        }

        if let bundleId = appId.split(separator: ":").first, !bundleId.isEmpty {
            return String(bundleId)
        }

        return appId
    }

    private func currentFrontmostBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func prepareArtifactsDirectory(at directoryURL: URL) {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            print("ShortcutCycle integration harness failed to create artifacts directory: \(error)")
        }
    }

    private func appendToEventLog(_ event: ShortcutCycleIntegrationEvent) {
        guard let configuration else { return }

        let logURL = configuration.artifactsDirectoryURL.appendingPathComponent(eventLogFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(event) else { return }

        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        } catch {
            print("ShortcutCycle integration harness failed to append event log: \(error)")
        }
    }

    private func startPollingCommandLog(using configuration: ShortcutCycleIntegrationConfiguration) {
        guard commandPollingTask == nil else { return }

        let commandLogURL = configuration.artifactsDirectoryURL.appendingPathComponent(commandLogFileName)
        commandPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollCommandLog(at: commandLogURL, runId: configuration.runId)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func pollCommandLog(at logURL: URL, runId: String) {
        guard let data = try? Data(contentsOf: logURL),
              let contents = String(data: data, encoding: .utf8),
              !contents.isEmpty else {
            return
        }

        let decoder = JSONDecoder()
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let lineData = line.data(using: .utf8),
                  let command = try? decoder.decode(ShortcutCycleIntegrationCommand.self, from: lineData),
                  command.runId == runId else {
                continue
            }
            handleIncomingCommand(command)
        }
    }
}

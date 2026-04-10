import Foundation
import OSLog
import os.signpost

@MainActor
final class GroupSwitchPerformanceTracker {
    static let shared = GroupSwitchPerformanceTracker()

    static let enabledDefaultsKey = "Debug.GroupSwitchPerformanceEnabled"

    private struct Session {
        let sequence: Int
        let signpostID: OSSignpostID
        let groupId: UUID
        let source: String
        let startedAtUptimeNanos: UInt64
        let expectedGroupIconCount: Int
        var headerVisibleAtUptimeNanos: UInt64?
        var shortcutSectionVisibleAtUptimeNanos: UInt64?
        var recorderMountedAtUptimeNanos: UInt64?
        var appsSectionVisibleAtUptimeNanos: UInt64?
        var quickAddRefreshStartedAtUptimeNanos: UInt64?
        var quickAddReadyAtUptimeNanos: UInt64?
        var firstGroupIconResolvedAtUptimeNanos: UInt64?
        var allGroupIconsResolvedAtUptimeNanos: UInt64?
        var resolvedGroupIconIDs: Set<UUID> = []
    }

    private let subsystem = Bundle.main.bundleIdentifier ?? "ShortcutCycle"
    private lazy var logger = Logger(subsystem: subsystem, category: "GroupSwitchPerformance")
    private lazy var signpostLog = OSLog(subsystem: subsystem, category: "GroupSwitchPerformance")
    private var currentSession: Session?
    private var nextSequence = 1

    private init() {}

    func beginGroupSwitch(
        to groupId: UUID,
        source: String,
        expectedGroupIconCount: Int
    ) {
        guard isEnabled else { return }
        guard currentSession?.groupId != groupId else { return }

        finishCurrentSession(reason: "superseded")

        let signpostID = OSSignpostID(log: signpostLog)
        var session = Session(
            sequence: nextSequence,
            signpostID: signpostID,
            groupId: groupId,
            source: source,
            startedAtUptimeNanos: nowUptimeNanos(),
            expectedGroupIconCount: expectedGroupIconCount
        )
        nextSequence += 1

        os_signpost(
            .begin,
            log: signpostLog,
            name: "GroupSwitch",
            signpostID: signpostID,
            "sequence=%{public}d source=%{public}@ group=%{public}@ app_count=%{public}d",
            session.sequence,
            session.source as NSString,
            session.groupId.uuidString as NSString,
            session.expectedGroupIconCount
        )

        logger.notice(
            "Group switch #\(session.sequence, privacy: .public) started source=\(session.source, privacy: .public) group=\(session.groupId.uuidString, privacy: .public) appCount=\(session.expectedGroupIconCount, privacy: .public)"
        )

        if expectedGroupIconCount == 0 {
            session.allGroupIconsResolvedAtUptimeNanos = session.startedAtUptimeNanos
            logEvent(
                "all group-app icons resolved",
                session: session,
                elapsedNanos: 0,
                extra: "count=0"
            )
        }

        currentSession = session
        maybeFinishCurrentSession()
    }

    func markHeaderVisible(for groupId: UUID) {
        guard var session = currentSession, session.groupId == groupId else { return }
        guard session.headerVisibleAtUptimeNanos == nil else { return }

        let now = nowUptimeNanos()
        session.headerVisibleAtUptimeNanos = now
        currentSession = session

        logEvent(
            "header visible",
            session: session,
            elapsedNanos: now - session.startedAtUptimeNanos
        )
        maybeFinishCurrentSession()
    }

    func markShortcutSectionVisible(for groupId: UUID) {
        guard var session = currentSession, session.groupId == groupId else { return }
        guard session.shortcutSectionVisibleAtUptimeNanos == nil else { return }

        let now = nowUptimeNanos()
        session.shortcutSectionVisibleAtUptimeNanos = now
        currentSession = session

        logEvent(
            "shortcut section visible",
            session: session,
            elapsedNanos: now - session.startedAtUptimeNanos
        )
        maybeFinishCurrentSession()
    }

    func markRecorderMounted(for groupId: UUID) {
        guard var session = currentSession, session.groupId == groupId else { return }
        guard session.recorderMountedAtUptimeNanos == nil else { return }

        let now = nowUptimeNanos()
        session.recorderMountedAtUptimeNanos = now
        currentSession = session

        logEvent(
            "recorder mounted",
            session: session,
            elapsedNanos: now - session.startedAtUptimeNanos
        )
        maybeFinishCurrentSession()
    }

    func markAppsSectionVisible(for groupId: UUID) {
        guard var session = currentSession, session.groupId == groupId else { return }
        guard session.appsSectionVisibleAtUptimeNanos == nil else { return }

        let now = nowUptimeNanos()
        session.appsSectionVisibleAtUptimeNanos = now
        currentSession = session

        logEvent(
            "apps section visible",
            session: session,
            elapsedNanos: now - session.startedAtUptimeNanos
        )
    }

    func markQuickAddRefreshStarted(for groupId: UUID) {
        guard var session = currentSession, session.groupId == groupId else { return }
        guard session.quickAddRefreshStartedAtUptimeNanos == nil else { return }

        let now = nowUptimeNanos()
        session.quickAddRefreshStartedAtUptimeNanos = now
        currentSession = session

        logEvent(
            "quick-add refresh started",
            session: session,
            elapsedNanos: now - session.startedAtUptimeNanos
        )
    }

    func markQuickAddReady(for groupId: UUID, candidateCount: Int) {
        guard var session = currentSession, session.groupId == groupId else { return }
        guard session.quickAddReadyAtUptimeNanos == nil else { return }

        let now = nowUptimeNanos()
        session.quickAddReadyAtUptimeNanos = now
        currentSession = session

        logEvent(
            "quick-add ready",
            session: session,
            elapsedNanos: now - session.startedAtUptimeNanos,
            extra: "candidate_count=\(candidateCount)"
        )
        maybeFinishCurrentSession()
    }

    func markGroupIconResolved(itemId: UUID, for groupId: UUID) {
        guard var session = currentSession, session.groupId == groupId else { return }
        guard session.expectedGroupIconCount > 0 else { return }
        guard session.resolvedGroupIconIDs.insert(itemId).inserted else { return }

        let now = nowUptimeNanos()
        if session.firstGroupIconResolvedAtUptimeNanos == nil {
            session.firstGroupIconResolvedAtUptimeNanos = now
            logEvent(
                "first group-app icon resolved",
                session: session,
                elapsedNanos: now - session.startedAtUptimeNanos
            )
        }

        if session.resolvedGroupIconIDs.count >= session.expectedGroupIconCount,
           session.allGroupIconsResolvedAtUptimeNanos == nil {
            session.allGroupIconsResolvedAtUptimeNanos = now
            logEvent(
                "all group-app icons resolved",
                session: session,
                elapsedNanos: now - session.startedAtUptimeNanos,
                extra: "count=\(session.expectedGroupIconCount)"
            )
        }

        currentSession = session
        maybeFinishCurrentSession()
    }

    private var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }

#if DEBUG
        return UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
#else
        return UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
#endif
    }

    private func maybeFinishCurrentSession() {
        guard
            let session = currentSession,
            session.recorderMountedAtUptimeNanos != nil,
            session.quickAddReadyAtUptimeNanos != nil
        else {
            return
        }

        finishCurrentSession(reason: "completed")
    }

    private func finishCurrentSession(reason: String) {
        guard let session = currentSession else { return }

        let end = nowUptimeNanos()
        let totalMilliseconds = milliseconds(from: session.startedAtUptimeNanos, to: end)
        os_signpost(
            .end,
            log: signpostLog,
            name: "GroupSwitch",
            signpostID: session.signpostID,
            "sequence=%{public}d reason=%{public}@ total_ms=%{public}.2f",
            session.sequence,
            reason as NSString,
            totalMilliseconds
        )

        logger.notice(
            "Group switch #\(session.sequence, privacy: .public) finished reason=\(reason, privacy: .public) total=\(self.formatMilliseconds(totalMilliseconds), privacy: .public)ms"
        )
        currentSession = nil
    }

    private func logEvent(
        _ name: StaticString,
        session: Session,
        elapsedNanos: UInt64,
        extra: String? = nil
    ) {
        let elapsedMilliseconds = Double(elapsedNanos) / 1_000_000
        let extraString = extra.map { " \($0)" } ?? ""

        os_signpost(
            .event,
            log: signpostLog,
            name: name,
            signpostID: session.signpostID,
            "sequence=%{public}d elapsed_ms=%{public}.2f extra=%{public}@",
            session.sequence,
            elapsedMilliseconds,
            extraString as NSString
        )

        logger.debug(
            "Group switch #\(session.sequence, privacy: .public) \(String(describing: name), privacy: .public) at \(self.formatMilliseconds(elapsedMilliseconds), privacy: .public)ms\(extraString, privacy: .public)"
        )
    }

    private func nowUptimeNanos() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(end - start) / 1_000_000
    }

    private func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

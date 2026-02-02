import XCTest
#if canImport(ShortcutCycleCore)
@testable import ShortcutCycleCore
#else
@testable import ShortcutCycle
#endif

final class BackupRetentionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func file(minutesAgo: Double) -> BackupRetention.TimedFile {
        let url = URL(fileURLWithPath: "/backups/backup-\(minutesAgo).json")
        return BackupRetention.TimedFile(url: url, date: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func file(hoursAgo: Double) -> BackupRetention.TimedFile {
        file(minutesAgo: hoursAgo * 60)
    }

    private func file(daysAgo: Double) -> BackupRetention.TimedFile {
        file(minutesAgo: daysAgo * 24 * 60)
    }

    // MARK: - Basic behavior

    func testEmptyListReturnsNoDeletions() {
        let result = BackupRetention.filesToDelete(from: [], now: now)
        XCTAssertEqual(result.count, 0)
    }

    func testSingleFileIsNeverDeleted() {
        let files = [file(minutesAgo: 5)]
        let result = BackupRetention.filesToDelete(from: files, now: now)
        XCTAssertEqual(result.count, 0)
    }

    func testNewestFileIsAlwaysKept() {
        let files = (0..<200).map { file(minutesAgo: Double($0)) }
        let deleted = Set(BackupRetention.filesToDelete(from: files, now: now))
        XCTAssertFalse(deleted.contains(files[0].url))
    }

    // MARK: - Recent tier (< 1 hour): keep all

    func testAllRecentFilesKept() {
        let files = (0..<50).map { file(minutesAgo: Double($0)) }
        let result = BackupRetention.filesToDelete(from: files, now: now)
        XCTAssertEqual(result.count, 0, "All files under 1 hour old should be kept")
    }

    // MARK: - Hourly tier (1h–24h): thin to 1 per hour

    func testHourlyTierThinsToOnePerHour() {
        // Create 3 files per hour for hours 1–5
        var files = [file(minutesAgo: 0)] // one recent
        for hour in 1...5 {
            for offset in [0, 20, 40] {
                files.append(file(minutesAgo: Double(hour * 60 + offset)))
            }
        }
        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        let kept = files.filter { f in !deleted.contains(f.url) }

        // Each hour bucket should keep exactly 1 file, plus the recent one
        // 1 recent + 5 hourly = 6
        XCTAssertEqual(kept.count, 6)
    }

    // MARK: - Daily tier (1d–30d): thin to 1 per day

    func testDailyTierThinsToOnePerDay() {
        // 3 files per day for days 2–5
        var files = [file(minutesAgo: 0)]
        for day in 2...5 {
            for hourOffset in [0, 6, 12] {
                files.append(file(hoursAgo: Double(day * 24 + hourOffset)))
            }
        }
        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        let kept = files.filter { f in !deleted.contains(f.url) }

        // 1 recent + 4 daily = 5
        XCTAssertEqual(kept.count, 5)
    }

    // MARK: - Weekly tier (30d+): thin to 1 per week

    func testWeeklyTierThinsToOnePerWeek() {
        // 3 files per week for weeks 5–8 (35–56 days ago)
        var files = [file(minutesAgo: 0)]
        for week in 5...8 {
            for dayOffset in [0, 2, 4] {
                files.append(file(daysAgo: Double(week * 7 + dayOffset)))
            }
        }
        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        let kept = files.filter { f in !deleted.contains(f.url) }

        // 1 recent + 4 weekly = 5
        XCTAssertEqual(kept.count, 5)
    }

    // MARK: - Max count enforcement

    func testMaxCountEnforced() {
        // Create 200 files spread across recent period (all < 1 hour, so all would be kept by tier rules)
        let files = (0..<200).map { file(minutesAgo: Double($0) * 0.25) }
        let deleted = BackupRetention.filesToDelete(from: files, now: now, maxCount: 100)
        let kept = files.count - deleted.count
        XCTAssertEqual(kept, 100)
    }

    func testMaxCountDropsOldestFirst() {
        let files = (0..<200).map { file(minutesAgo: Double($0) * 0.25) }
        let deletedURLs = Set(BackupRetention.filesToDelete(from: files, now: now, maxCount: 100))

        // The 100 newest should be kept
        for i in 0..<100 {
            XCTAssertFalse(deletedURLs.contains(files[i].url), "File at index \(i) should be kept")
        }
    }

    // MARK: - Mixed tiers

    func testMixedTiersRetainCorrectly() {
        var files: [BackupRetention.TimedFile] = []

        // 5 recent (< 1h)
        for i in 0..<5 { files.append(file(minutesAgo: Double(i * 10))) }
        // 10 in hourly tier (2h–11h ago), 2 per hour
        for h in 2...6 {
            files.append(file(hoursAgo: Double(h)))
            files.append(file(hoursAgo: Double(h) + 0.5))
        }
        // 6 in daily tier (2d–4d), 2 per day
        for d in 2...4 {
            files.append(file(daysAgo: Double(d)))
            files.append(file(daysAgo: Double(d) + 0.25))
        }

        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        let kept = files.count - deleted.count

        // 5 recent + 5 hourly + 3 daily = 13
        XCTAssertEqual(kept, 13)
    }
}

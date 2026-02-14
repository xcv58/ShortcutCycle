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

    func testTwoFilesNeitherDeleted() {
        let files = [file(minutesAgo: 0), file(minutesAgo: 30)]
        let result = BackupRetention.filesToDelete(from: files, now: now)
        XCTAssertEqual(result.count, 0)
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

    func testMaxCountOfOne() {
        let files = (0..<10).map { file(minutesAgo: Double($0) * 5) }
        let deleted = BackupRetention.filesToDelete(from: files, now: now, maxCount: 1)
        let kept = files.count - deleted.count
        XCTAssertEqual(kept, 1)

        // Only the newest should survive
        let deletedURLs = Set(deleted)
        XCTAssertFalse(deletedURLs.contains(files[0].url))
    }

    func testMaxCountEqualToFileCount() {
        let files = (0..<5).map { file(minutesAgo: Double($0) * 10) }
        let deleted = BackupRetention.filesToDelete(from: files, now: now, maxCount: 5)
        // All are recent (< 1h), tier keeps all, max count matches => no deletions
        XCTAssertEqual(deleted.count, 0)
    }

    func testMaxCountGreaterThanFileCount() {
        let files = (0..<3).map { file(minutesAgo: Double($0) * 10) }
        let deleted = BackupRetention.filesToDelete(from: files, now: now, maxCount: 100)
        XCTAssertEqual(deleted.count, 0)
    }

    // MARK: - Tier boundary edge cases

    func testFileAtExactlyOneHourBoundary() {
        // A file aged exactly 60 minutes (1 hour) is at the boundary between recent and hourly
        var files = [file(minutesAgo: 0)]
        files.append(file(minutesAgo: 60.0)) // exactly 1 hour

        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        // Two files, boundary file enters hourly tier, but it's the only one in its bucket
        XCTAssertEqual(deleted.count, 0)
    }

    func testFileAtExactly24HourBoundary() {
        // File aged exactly 24 hours is at boundary between hourly and daily tiers
        var files = [file(minutesAgo: 0)]
        files.append(file(hoursAgo: 24.0)) // exactly 24 hours

        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        XCTAssertEqual(deleted.count, 0)
    }

    func testFileAtExactly30DayBoundary() {
        // File aged exactly 30 days is at boundary between daily and weekly tiers
        var files = [file(minutesAgo: 0)]
        files.append(file(daysAgo: 30.0)) // exactly 30 days

        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        XCTAssertEqual(deleted.count, 0)
    }

    func testTwoFilesInSameHourBucketKeepsNewest() {
        // Two files in the same 1-hour bucket during hourly tier
        var files = [file(minutesAgo: 0)] // recent
        files.append(file(minutesAgo: 65))  // 1h5m ago (bucket 1)
        files.append(file(minutesAgo: 110)) // 1h50m ago (bucket 1)

        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        let deletedURLs = Set(deleted)

        // Should keep the newer one in the bucket (65 min ago)
        XCTAssertFalse(deletedURLs.contains(files[1].url), "Newer file in bucket should be kept")
        XCTAssertTrue(deletedURLs.contains(files[2].url), "Older file in bucket should be deleted")
    }

    func testTwoFilesInSameDayBucketKeepsNewest() {
        // Two files in the same daily bucket
        var files = [file(minutesAgo: 0)]
        files.append(file(daysAgo: 3.0))   // 3 days ago
        files.append(file(daysAgo: 3.5))   // 3.5 days ago (same day bucket)

        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        let deletedURLs = Set(deleted)

        // Should keep the newer one
        XCTAssertFalse(deletedURLs.contains(files[1].url))
        XCTAssertTrue(deletedURLs.contains(files[2].url))
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

    // MARK: - Very old files

    func testVeryOldFilesInWeeklyTier() {
        var files = [file(minutesAgo: 0)]
        // Files from 100-200 days ago (3+ months)
        for day in stride(from: 100, through: 200, by: 1) {
            files.append(file(daysAgo: Double(day)))
        }
        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        let kept = files.count - deleted.count

        // All should be thinned to ~1 per week in the weekly tier + the 1 newest
        // ~100 days / 7 ≈ ~14 weekly buckets + 1 newest
        XCTAssertLessThanOrEqual(kept, 16)
        XCTAssertGreaterThanOrEqual(kept, 14)
    }

    func testDefaultMaxCount() {
        XCTAssertEqual(BackupRetention.defaultMaxCount, 100)
    }

    // MARK: - All tiers exercised

    func testFilesSpanningAllFourTiers() {
        var files: [BackupRetention.TimedFile] = []

        // Recent tier (< 1h): 3 files
        for i in 0..<3 { files.append(file(minutesAgo: Double(i * 15))) }
        // Hourly tier (1h-24h): 6 files, 2 per hour in hours 2-4
        for h in 2...4 {
            files.append(file(hoursAgo: Double(h)))
            files.append(file(hoursAgo: Double(h) + 0.3))
        }
        // Daily tier (1d-30d): 6 files, 2 per day in days 3-5
        for d in 3...5 {
            files.append(file(daysAgo: Double(d)))
            files.append(file(daysAgo: Double(d) + 0.4))
        }
        // Weekly tier (30d+): 6 files, 2 per week in weeks 5-7
        for w in 5...7 {
            files.append(file(daysAgo: Double(w * 7)))
            files.append(file(daysAgo: Double(w * 7 + 3)))
        }

        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        let kept = files.count - deleted.count

        // 3 recent + 3 hourly + 3 daily + 3 weekly = 12
        XCTAssertEqual(kept, 12)
    }

    func testOlderFileInBucketIsNotKept() {
        // Specifically test that when two files are in the same bucket,
        // the older one (with larger age) is deleted
        var files = [file(minutesAgo: 0)]
        // Two files in hour-3 bucket: one at 3h, one at 3h40m
        files.append(file(hoursAgo: 3.0))
        files.append(file(hoursAgo: 3.67)) // 3h40m

        let deleted = BackupRetention.filesToDelete(from: files, now: now)
        let deletedURLs = Set(deleted)

        // The 3h40m file should be deleted (it's older in the same bucket)
        XCTAssertTrue(deletedURLs.contains(files[2].url))
        XCTAssertFalse(deletedURLs.contains(files[1].url))
    }

    // MARK: - Bucket selection

    func testNewestPerBucketPrefersNewestEvenIfUnsorted() {
        let older = BackupRetention.TimedFile(
            url: URL(fileURLWithPath: "/backups/old.json"),
            date: now.addingTimeInterval(-3600)
        )
        let newer = BackupRetention.TimedFile(
            url: URL(fileURLWithPath: "/backups/new.json"),
            date: now.addingTimeInterval(-1800)
        )

        let kept = BackupRetention.newestPerBucket(
            [older, newer],
            interval: 3600,
            referenceDate: now
        )

        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.url, newer.url)
    }
}

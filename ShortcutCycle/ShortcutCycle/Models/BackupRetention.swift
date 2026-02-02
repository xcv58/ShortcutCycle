import Foundation

/// GFS-style (Grandfather-Father-Son) backup retention policy.
///
/// Thins backup files by keeping progressively fewer backups for older time periods:
/// - Recent (< 1 hour): keep all
/// - Last 24 hours: keep 1 per hour
/// - Last 30 days: keep 1 per day
/// - Older: keep 1 per week
///
/// After thinning, enforces an absolute cap to bound disk usage.
struct BackupRetention {

    struct TimedFile {
        let url: URL
        let date: Date
    }

    /// Tiers define how aggressively to thin backups based on age.
    /// Within each tier's time range, only one backup per `bucketInterval` is kept.
    /// The newest file in each bucket wins (the most complete state for that period).
    private struct Tier {
        let name: String
        let maxAge: TimeInterval      // files older than this move to the next tier
        let bucketInterval: TimeInterval  // keep one file per this interval
    }

    private static let tiers: [Tier] = [
        Tier(name: "recent",  maxAge:  1 * 3600,      bucketInterval: 0),           // < 1h: keep all
        Tier(name: "hourly",  maxAge: 24 * 3600,      bucketInterval: 1 * 3600),    // 1h–24h: 1 per hour
        Tier(name: "daily",   maxAge: 30 * 24 * 3600,  bucketInterval: 24 * 3600),  // 1d–30d: 1 per day
        Tier(name: "weekly",  maxAge: .infinity,        bucketInterval: 7 * 24 * 3600), // 30d+: 1 per week
    ]

    static let defaultMaxCount = 100

    /// Given a list of backup files with their dates, returns the URLs to delete.
    static func filesToDelete(
        from files: [TimedFile],
        now: Date = Date(),
        maxCount: Int = defaultMaxCount
    ) -> [URL] {
        guard files.count > 1 else { return [] }

        let sorted = files.sorted { $0.date > $1.date } // newest first
        var keep = Set<URL>()

        // Always keep the newest file
        keep.insert(sorted[0].url)

        // Assign each file to a tier based on its age, then thin within each tier
        var remaining = Array(sorted.dropFirst())

        var tierStart: TimeInterval = 0
        for tier in tiers {
            let tierFiles = remaining.filter { file in
                let age = now.timeIntervalSince(file.date)
                return age >= tierStart && age < tier.maxAge
            }
            remaining.removeAll { file in
                let age = now.timeIntervalSince(file.date)
                return age >= tierStart && age < tier.maxAge
            }

            if tier.bucketInterval == 0 {
                // Keep all files in this tier
                for file in tierFiles {
                    keep.insert(file.url)
                }
            } else {
                // Bucket by interval, keep the newest file in each bucket
                let kept = newestPerBucket(tierFiles, interval: tier.bucketInterval, referenceDate: now)
                for file in kept {
                    keep.insert(file.url)
                }
            }

            tierStart = tier.maxAge
            if tierStart == .infinity { break }
        }

        // Enforce absolute cap: if still over maxCount, drop the oldest keepers
        if keep.count > maxCount {
            let keepSorted = sorted.filter { keep.contains($0.url) }
            let toDrop = keepSorted.dropFirst(maxCount)
            for file in toDrop {
                keep.remove(file.url)
            }
        }

        // Everything not in `keep` should be deleted
        return sorted.filter { !keep.contains($0.url) }.map(\.url)
    }

    /// Groups files into time buckets and returns the newest file from each bucket.
    private static func newestPerBucket(
        _ files: [TimedFile],
        interval: TimeInterval,
        referenceDate: Date
    ) -> [TimedFile] {
        // Bucket key = floor(age / interval)
        var buckets: [Int: TimedFile] = [:]
        for file in files {
            let age = referenceDate.timeIntervalSince(file.date)
            let key = Int(age / interval)
            if let existing = buckets[key] {
                // Keep the newer one (smaller age = more recent)
                if file.date > existing.date {
                    buckets[key] = file
                }
            } else {
                buckets[key] = file
            }
        }
        return Array(buckets.values)
    }
}

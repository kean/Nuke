// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: A last sweep date in the future turns the scheduled LRU sweeps off
// until the clock catches up with it.
//
// `isSweepNeeded()` (Sources/Nuke/Caching/DataCache.swift:554-559) checks
// `Date().timeIntervalSince(lastSweepDate) >= sweepInterval`. When the date
// recorded in `.data-cache-info` is ahead of the current clock – the device
// clock was wrong (set forward manually, bad NTP) when a sweep ran and was
// corrected later, or the cache directory was restored from another device –
// the interval is negative, so every scheduled sweep is skipped until the
// clock reaches the recorded date, which can be months or years away. The
// skipped sweeps don't rewrite the metadata, so nothing repairs it short of
// an explicit `sweep()`, and meanwhile the cache grows past `sizeLimit`
// without bound.
//
// The docs promise the opposite: "The sweeps are performed periodically for
// as long as the cache is alive" (DataCache class docs), and the first sweep
// "is skipped if one was already performed within the interval" – a sweep
// dated a year from now was not performed within the last 30 minutes.
//
// Expected: a recorded date that isn't in the past doesn't count as a recent
//           sweep, so the launch sweep runs and trims the cache.
// Actual:   the scheduled sweep is skipped: `onSweepCompleted` is never
//           called and the cache stays over its size limit.
@Suite(.timeLimit(.minutes(5)))
struct DataCacheFutureSweepDateBugRepro {
    private struct Metadata: Codable {
        var lastSweepDate: Date?
    }

    @Test func sweepDateInTheFutureDoesNotSuppressTheScheduledSweep() async throws {
        // GIVEN a cache directory over its size limit whose last sweep is
        // dated a year from now
        let name = "DataCacheFutureSweepDateBugRepro-\(UUID().uuidString)"
        let path = URL.cachesDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: path) }
        let metadata = Metadata(lastSweepDate: Date(timeIntervalSinceNow: 365 * 24 * 3600))
        try JSONEncoder().encode(metadata).write(to: path.appendingPathComponent(".data-cache-info"))
        for index in 0..<4 {
            try Data(repeating: UInt8(index), count: 1024 * 1024)
                .write(to: path.appendingPathComponent("entry\(index)"))
        }

        // WHEN the app launches
        let expectation = TestExpectation()
        let cache = try DataCache(
            name: name,
            sweepDelay: .milliseconds(500), // Lets the size limit below land before the sweep reads it
            onSweepCompleted: { expectation.fulfill() }
        )
        cache.sizeLimit = 1024 * 1024

        // THEN the launch sweep runs
        await expectation.wait(timeout: .seconds(10)) // Actual: times out
        #expect(cache.totalSize <= 1024 * 1024) // Actual: 4 MB
        cache.isSweepEnabled = false
    }
}

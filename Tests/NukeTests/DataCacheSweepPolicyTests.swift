// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

private let mb = 1024 * 1024

/// The file where ``DataCache`` keeps the date of its last sweep.
func metadataURL(at path: URL) -> URL {
    path.appendingPathComponent(".data-cache-info", isDirectory: false)
}

struct SweepMetadata: Codable {
    var lastSweepDate: Date?
}

func lastSweepDate(at path: URL) -> Date? {
    guard let data = try? Data(contentsOf: metadataURL(at: path)) else {
        return nil
    }
    return try? JSONDecoder().decode(SweepMetadata.self, from: data).lastSweepDate
}

@Suite(.timeLimit(.minutes(5)))
struct DataCacheConfigurationTests {
    @Test func defaults() throws {
        // GIVEN
        let cache = try DataCache(path: makeUniqueDirectoryURL())
        defer { try? FileManager.default.removeItem(at: cache.path) }

        // THEN the values match the documentation
        #expect(cache.sizeLimit == 150 * mb)
        #expect(cache.sweepInterval == 1800)
        #expect(cache.isSweepEnabled)
        #expect(cache.trimRatio == 0.7)
        #expect(cache.flushInterval == .seconds(1))
    }

    @Test func configurationChangesAreReadBack() throws {
        // GIVEN
        let cache = try DataCache(path: makeUniqueDirectoryURL())
        defer { try? FileManager.default.removeItem(at: cache.path) }

        // WHEN
        cache.sizeLimit = 42
        cache.sweepInterval = 60
        cache.isSweepEnabled = false
        cache.trimRatio = 0.5
        cache.flushInterval = .milliseconds(250)

        // THEN
        #expect(cache.sizeLimit == 42)
        #expect(cache.sweepInterval == 60)
        #expect(!cache.isSweepEnabled)
        #expect(cache.trimRatio == 0.5)
        #expect(cache.flushInterval == .milliseconds(250))
    }

    @Test func customFilenameGeneratorDeterminesTheLocationOfTheEntries() async throws {
        // GIVEN
        let path = makeUniqueDirectoryURL()
        let cache = try DataCache(path: path, filenameGenerator: { "entry-" + $0 })
        defer { try? FileManager.default.removeItem(at: cache.path) }
        cache.isSweepEnabled = false

        // WHEN
        cache["key"] = Data("123".utf8)
        await cache.flush()

        // THEN
        #expect(cache.filename(for: "key") == "entry-key")
        #expect(cache.url(for: "key") == path.appendingPathComponent("entry-key", isDirectory: false))
        #expect(try Data(contentsOf: path.appendingPathComponent("entry-key")) == Data("123".utf8))
        // The static default is unaffected by the instance's generator
        #expect(DataCache.filename(for: "key") == "key".sha1)
    }
}

/// When the LRU sweep runs and what it chooses to remove.
@Suite(.timeLimit(.minutes(5)))
final class DataCacheSweepPolicyTests {
    private let cache: DataCache

    init() throws {
        cache = try DataCache(path: makeUniqueDirectoryURL())
        // Only the sweeps performed by the tests themselves; the scheduled
        // one could otherwise run in the middle of a test.
        cache.isSweepEnabled = false
    }

    deinit {
        cache.suspendIO()
        try? FileManager.default.removeItem(at: cache.path)
    }

    /// Stamps the access dates so that `keys[0]` is the least recently used
    /// entry and the last key is the most recently used one.
    ///
    /// The modification dates go further back than the access dates: APFS
    /// refreshes the access date of a file it reads only while it's older
    /// than the modification date, and the tests need the date to change
    /// only when the cache refreshes it.
    private func stampAccessDates(inOrder keys: [String]) throws {
        let now = Date()
        for (index, key) in keys.enumerated() {
            var url = try #require(cache.url(for: key))
            var values = URLResourceValues()
            values.contentModificationDate = now.addingTimeInterval(-10_000)
            values.contentAccessDate = now.addingTimeInterval(TimeInterval(index - keys.count - 1) * 100)
            try url.setResourceValues(values)
        }
    }

    // MARK: Limits

    @Test func sweepLeavesTheCacheAloneWhenItIsExactlyAtTheSizeLimit() async {
        // GIVEN
        for index in 1...3 {
            cache["key\(index)"] = Data(repeating: UInt8(index), count: 64 * 1024)
        }
        await cache.flush()
        let size = cache.totalAllocatedSize
        #expect(size > 0)

        // WHEN the limit matches the size exactly
        cache.sizeLimit = size
        await cache.sweep()

        // THEN it's not over the limit
        #expect(cache.totalCount == 3)

        // WHEN it's one byte short
        cache.sizeLimit = size - 1
        await cache.sweep()

        // THEN the sweep trims it down to the trim ratio
        #expect(cache.totalCount < 3)
        #expect(Double(cache.totalAllocatedSize) <= Double(size - 1) * 0.7)
    }

    @Test func sweepWithAZeroSizeLimitRemovesEverything() async {
        // GIVEN
        for index in 1...3 {
            cache["key\(index)"] = Data(repeating: UInt8(index), count: 1024)
        }
        await cache.flush()

        // WHEN
        cache.sizeLimit = 0
        await cache.sweep()

        // THEN
        #expect(cache.totalCount == 0)
        for index in 1...3 {
            #expect(cache["key\(index)"] == nil)
        }
    }

    /// ``DataCache/isSweepEnabled`` turns off the automatic sweeps only.
    @Test func explicitSweepRunsWhenTheAutomaticSweepIsDisabled() async {
        // GIVEN a cache over its limit with the automatic sweep turned off
        #expect(!cache.isSweepEnabled)
        cache.sizeLimit = mb * 2
        for index in 1...4 {
            cache["key\(index)"] = Data(repeating: UInt8(index), count: mb)
        }
        await cache.flush()

        // WHEN
        await cache.sweep()

        // THEN
        #expect(cache.totalSize <= mb * 2)
        #expect(lastSweepDate(at: cache.path) != nil)
    }

    // MARK: LRU

    @Test func readingAnEntryMovesItToTheFrontOfTheLRUOrder() async throws {
        // GIVEN four entries with `key1` the least recently used one and a
        // limit that fits two of them after the trim
        let keys = (1...4).map { "key\($0)" }
        for key in keys {
            cache[key] = Data(repeating: 1, count: mb)
        }
        await cache.flush()
        try stampAccessDates(inOrder: keys)
        cache.sizeLimit = mb * 3 // The trim ratio takes it down to 2.1 MB

        // WHEN the least recently used entry is read
        #expect(cache.cachedData(for: "key1") != nil)
        await cache.flush() // Writes the new access date

        await cache.sweep()

        // THEN it survives the sweep, and the next oldest ones go instead
        #expect(cache.containsData(for: "key1"))
        #expect(cache.containsData(for: "key4"))
        #expect(!cache.containsData(for: "key2"))
        #expect(!cache.containsData(for: "key3"))
    }

    @Test func overwritingAnEntryMovesItToTheFrontOfTheLRUOrder() async throws {
        // GIVEN four entries with `key1` the least recently used one
        let keys = (1...4).map { "key\($0)" }
        for key in keys {
            cache[key] = Data(repeating: 1, count: mb)
        }
        await cache.flush()
        try stampAccessDates(inOrder: keys)
        cache.sizeLimit = mb * 3

        // WHEN the least recently used entry is replaced
        cache["key1"] = Data(repeating: 2, count: mb)
        await cache.flush()

        await cache.sweep()

        // THEN the new file doesn't inherit the stale date
        #expect(cache["key1"] == Data(repeating: 2, count: mb))
        #expect(cache.containsData(for: "key4"))
        #expect(!cache.containsData(for: "key2"))
        #expect(!cache.containsData(for: "key3"))
    }
}

/// The scheduled sweeps, which are driven by the metadata file.
@Suite(.timeLimit(.minutes(5)))
struct DataCacheScheduledSweepTests {
    @Test func corruptMetadataDoesNotPreventTheScheduledSweep() async throws {
        // GIVEN a metadata file that isn't valid JSON next to an entry
        let path = URL.cachesDirectory.appendingPathComponent("DataCacheScheduledSweepTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: path) }
        try Data("not json".utf8).write(to: metadataURL(at: path))
        let filename = try #require(DataCache.filename(for: "key"))
        try Data("123".utf8).write(to: path.appendingPathComponent(filename))

        // WHEN
        let expectation = TestExpectation()
        let cache = try DataCache(
            name: path.lastPathComponent,
            sweepDelay: .milliseconds(0),
            onSweepCompleted: { expectation.fulfill() }
        )
        await expectation.wait()

        // THEN the sweep runs and replaces it with a valid one
        let date = try #require(lastSweepDate(at: path))
        #expect(abs(date.timeIntervalSinceNow) < 60)
        // AND the entries are unaffected
        #expect(cache["key"] == Data("123".utf8))
        #expect(cache.totalCount == 1)
        cache.isSweepEnabled = false
        await cache.flush() // The read's access date, before the directory goes
    }

    /// The interval is read when the sweep runs, not when the cache is
    /// created, so shortening it catches up on a sweep that's due.
    @Test func sweepIntervalChangedAfterInitDecidesWhetherTheSweepIsDue() async throws {
        // GIVEN the last sweep a minute ago – recent enough for the default
        // interval (30 minutes) to skip the next one
        let path = URL.cachesDirectory.appendingPathComponent("DataCacheScheduledSweepTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: path) }
        try JSONEncoder().encode(SweepMetadata(lastSweepDate: Date(timeIntervalSinceNow: -60))).write(to: metadataURL(at: path))
        let lastSweep = try #require(lastSweepDate(at: path))
        let cache = try DataCache(
            name: path.lastPathComponent,
            sweepDelay: .seconds(100), // The test performs the sweeps itself
            onSweepCompleted: {}
        )
        await cache.performScheduledSweepForTesting()
        #expect(lastSweepDate(at: path) == lastSweep)

        // WHEN the interval is shortened after the cache is created
        cache.sweepInterval = 10
        await cache.performScheduledSweepForTesting()

        // THEN the sweep is due
        let date = try #require(lastSweepDate(at: path))
        #expect(date > lastSweep)
    }
}

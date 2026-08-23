// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Security
@testable import Nuke

private let blob = "123".data(using: .utf8)
private let otherBlob = "456".data(using: .utf8)
private let trafficKeyCount = 10

@Suite(.timeLimit(.minutes(5)))
final class DataCacheTests {
    private let cache: DataCache

    init() throws {
        cache = try DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) }
        )
    }

    deinit {
        // The I/O has to be stopped first: a test that leaves changes staged
        // ends with a drain scheduled after the flush interval, and it would
        // re-create the directory to write them after it is removed here.
        cache.suspendIO()
        try? FileManager.default.removeItem(at: cache.path)
    }

    // MARK: Init

    @Test func initWithName() throws {
        // Given
        let name = UUID().uuidString

        // When
        let cache = try DataCache(name: name, filenameGenerator: { $0 })
        defer { try? FileManager.default.removeItem(at: cache.path) }

        // Then
        #expect(cache.path.lastPathComponent == name)
        #expect(FileManager.default.fileExists(atPath: cache.path.path))
    }

    @Test func initWithPath() throws {
        // Given
        let name = UUID().uuidString
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(name)

        // When
        let cache = try DataCache(path: path, filenameGenerator: { $0 })
        defer { try? FileManager.default.removeItem(at: cache.path) }

        // Then
        #expect(cache.path == path)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    // MARK: Default Key Encoder

    @Test func defaultKeyEncoder() throws {
        let cache = try DataCache(name: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache.path) }
        let filename = cache.filename(for: "http://test.com")
        #expect(filename == "50334ee0b51600df6397ce93ceed4728c37fee4e")
    }

    @Test func sha1() {
        #expect("http://test.com".sha1 == "50334ee0b51600df6397ce93ceed4728c37fee4e")
    }

    // MARK: Add

    @Test func add() {
        cache.withSuspendedIO {
            // When
            cache["key"] = blob

            // Then
            #expect(cache["key"] == blob)
        }
    }

    @Test func whenAddContentNotFlushedImmediately() {
        cache.withSuspendedIO {
            // When
            cache["key"] = blob

            // Then
            #expect(cache.contents.count == 0)
        }
    }

    @Test func addAndFlush() async {
        // Given
        cache.withSuspendedIO {
            cache["key"] = blob
        }

        // When
        await cache.flush()

        // Then
        #expect(cache.contents.count == 1)
        #expect(cache["key"] == blob)
        #expect((try? Data(contentsOf: cache.contents.first!)) == blob)
    }

    @Test func replace() {
        cache.withSuspendedIO {
            // Given
            cache["key"] = blob

            // When
            cache["key"] = otherBlob

            // Then
            #expect(cache["key"] == otherBlob)
        }
    }

    @Test func replaceFlushed() async {
        // Given
        cache["key"] = blob
        await cache.flush()

        cache.withSuspendedIO {
            cache["key"] = otherBlob
            #expect(cache.contents.count == 1)
            // Test that before flush we still have the old blob on disk,
            // but new blob in staging
            #expect((try? Data(contentsOf: cache.contents.first!)) == blob)
            #expect(cache["key"] == otherBlob)
        }

        // Flush and test that data on disk was updated.
        await cache.flush()
        #expect(cache.contents.count == 1)
        #expect((try? Data(contentsOf: cache.contents.first!)) == otherBlob)
        #expect(cache["key"] == otherBlob)
    }

    // MARK: Removal

    @Test func removeNonExistent() async {
        cache["key"] = nil
        await cache.flush()
    }

    // - Remove + write (new) staged -> remove from staging
    @Test func removeFromStaging() async {
        cache.withSuspendedIO {
            cache["key"] = blob
            cache["key"] = nil
            #expect(cache["key"] == nil)
        }
        await cache.flush()
        #expect(cache["key"] == nil)
    }

    // - Remove + write (new) staged -> remove from staging
    @Test func removeReplaced() async {
        cache.withSuspendedIO {
            cache["key"] = blob
            cache["key"] = otherBlob
            cache["key"] = nil
        }
        await cache.flush()
        #expect(cache["key"] == nil)
        #expect(cache.contents.count == 0)
    }

    // - Remove + write (replace) staged -> schedule removal
    @Test func removeReplacedFlushed() async {
        cache["key"] = blob
        await cache.flush()

        cache.withSuspendedIO {
            cache["key"] = otherBlob
            cache["key"] = nil
            #expect(cache["key"] == nil)
            #expect((try? Data(contentsOf: cache.contents.first!)) == blob)
        }

        await cache.flush() // Should still perform deletion of "blob"
        #expect(cache.contents.count == 0)
    }

    // - Remove + flushed -> schedule removal
    @Test func removeFlushed() async {
        // Given
        cache["key"] = blob
        await cache.flush()

        cache.withSuspendedIO {
            cache["key"] = nil
            #expect(cache["key"] == nil)
            // Still have data in cache
            #expect(cache.contents.count == 1)
            #expect((try? Data(contentsOf: cache.contents.first!)) == blob)
        }
        await cache.flush()

        #expect(cache["key"] == nil)

        // IO performed
        #expect(cache.contents.count == 0)
    }

    // - Remove + removal staged -> noop
    @Test func removeWhenRemovalAlreadyScheduled() async {
        // Given
        cache["key"] = blob
        await cache.flush()

        // When
        cache["key"] = nil
        cache["key"] = nil
        await cache.flush()

        // Then
        #expect(cache.contents.count == 0)
    }

    @Test func removeAndThenReplace() async {
        // Given
        cache["key"] = blob
        await cache.flush()

        // When
        cache["key"] = nil
        cache["key"] = blob
        await cache.flush()

        // Then
        #expect(cache["key"] == blob)
        #expect(cache.contents.count == 1)
        #expect((try? Data(contentsOf: cache.contents.first!)) == blob)
    }

    // MARK: Remove All

    @Test func removeAll() {
        cache.withSuspendedIO {
            // Given
            cache["key"] = blob

            // When
            cache.removeAll()

            // Then
            #expect(cache["key"] == nil)
        }
    }

    @Test func removeAllFlushed() async {
        // Given
        cache["key"] = blob
        await cache.flush()

        // When
        cache.withSuspendedIO {
            cache.removeAll()
            #expect(cache["key"] == nil)
        }
    }

    @Test func removeAllFlushedAndFlush() async {
        // Given
        cache["key"] = blob
        await cache.flush()

        // When
        cache.removeAll()
        await cache.flush()

        // Then
        #expect(cache["key"] == nil)
        #expect(cache.contents.count == 0)
    }

    @Test func removeAllAndAdd() {
        // Given
        cache.withSuspendedIO {
            cache["key"] = blob

            // When
            cache.removeAll()
            cache["key"] = blob

            // Then
            #expect(cache["key"] == blob)
        }
    }

    @Test func removeAllTwice() {
        // Given
        cache.withSuspendedIO {
            cache["key"] = blob

            // When
            cache.removeAll()
            cache["key"] = blob
            cache.removeAll()

            // Then
            #expect(cache["key"] == nil)
        }
    }

    // MARK: DataCaching

    @Test func getCachedDataHitFromStaging() {
        // Given data that is only in the staging area
        cache.withSuspendedIO {
            cache["key"] = blob

            // When/Then
            let data = cache.cachedData(for: "key")
            #expect(data == blob)
        }
    }

    @Test func getCachedData() async {
        // Given
        cache["key"] = blob
        await cache.flush()

        // When/Then
        let data = cache.cachedData(for: "key")
        #expect(data == blob)
    }

    // MARK: Flush

    @Test func flush() async {
        // Given
        cache.withSuspendedIO {
            cache["key"] = blob
        }

        // When
        await cache.flush()

        // Then
        #expect(cache.contents == [cache.url(for: "key")].compactMap { $0 })
    }

    @Test func flushWritesTheChangesTheDrainHasNotPickedUpYet() async {
        // GIVEN two changes staged behind an interval the automatic drain is
        // still waiting through
        cache.flushInterval = .seconds(20)
        cache["key1"] = blob
        cache["key2"] = otherBlob

        // WHEN
        await cache.flush()

        // THEN the flush performed the work itself instead of waiting for the
        // automatic drain to get to it
        #expect(cache.contents.count == 2)
    }

    @Test func flushReturnsUnderSustainedWriteTraffic() async {
        // GIVEN a steady stream of writes that never lets the cache go idle.
        // The keys are recycled so that the traffic can't grow the cache
        // without a bound for as long as the test runs.
        let cache = self.cache
        let traffic = Task.detached {
            var index = 0
            while !Task.isCancelled {
                cache["traffic\(index % trafficKeyCount)"] = blob
                index += 1
                await Task.yield()
            }
        }
        cache["key"] = blob

        // WHEN
        await cache.flush() // Must return instead of chasing the traffic

        // THEN
        #expect(cache.containsData(for: "key"))
        traffic.cancel()
        _ = await traffic.value
        await cache.flush() // Drain what the traffic left behind
    }

    @Test func concurrentFlushesAllReturn() async {
        // GIVEN
        let cache = self.cache
        cache.flushInterval = .seconds(20)
        cache["key1"] = blob
        cache["key2"] = otherBlob

        // WHEN two flushes are pending at the same time
        async let first: Void = cache.flush()
        async let second: Void = cache.flush()
        _ = await (first, second)

        // THEN
        #expect(cache.contents.count == 2)
    }

    // MARK: Throttling

    @Test func stagedChangesAreDrainedWithoutAnExplicitFlush() async throws {
        // GIVEN an interval short enough to keep the test quick
        cache.flushInterval = .milliseconds(10)

        // WHEN
        cache["key"] = blob

        // THEN the drain gets to it on its own once the interval is over
        while cache.contents.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(cache.contents == [cache.url(for: "key")].compactMap { $0 })
    }

    @Test func writesWithinTheFlushIntervalAreCoalesced() async {
        // GIVEN an interval long enough that the drain can't run within it
        cache.flushInterval = .seconds(20)

        // WHEN
        cache["key1"] = blob
        cache["key2"] = otherBlob

        // THEN the changes wait in the staging area instead of reaching the
        // disk one by one
        #expect(cache.contents.isEmpty)
        #expect(cache.cachedData(for: "key1") == blob)

        // AND an explicit flush isn't held up by the interval
        await cache.flush()
        #expect(cache.contents.count == 2)
    }

    // MARK: Sweep

    @Test func sweep() async {
        // GIVEN
        let mb = 1024 * 1024 // allocated size is usually about 4 KB on APFS, so use 1 MB just to be sure
        cache.sizeLimit = mb * 3
        cache["key1"] = Data(repeating: 1, count: mb)
        cache["key2"] = Data(repeating: 1, count: mb)
        cache["key3"] = Data(repeating: 1, count: mb)
        cache["key4"] = Data(repeating: 1, count: mb)
        await cache.flush()

        // WHEN
        await cache.sweep()

        // THEN
        #expect(cache.totalSize == mb * 2)
    }

    @Test func sweepReducesTotalCount() async {
        // GIVEN - 5 entries, limit fits only 3
        let mb = 1024 * 1024
        cache.sizeLimit = mb * 3
        for i in 1...5 {
            cache["key\(i)"] = Data(repeating: UInt8(i), count: mb)
        }
        await cache.flush()

        // WHEN
        await cache.sweep()

        // THEN - at most 3 MB worth of entries remain
        #expect(cache.totalCount <= 3)
        #expect(cache.totalSize <= mb * 3)
    }

    @Test func sweepIsNoOpWhenUnderLimit() async {
        // GIVEN - total size well under the limit
        let mb = 1024 * 1024
        cache.sizeLimit = mb * 10
        cache["small1"] = Data(repeating: 1, count: mb)
        cache["small2"] = Data(repeating: 2, count: mb)
        await cache.flush()

        let countBefore = cache.totalCount

        // WHEN
        await cache.sweep()

        // THEN - nothing is removed
        #expect(cache.totalCount == countBefore)
    }

    @Test func sweepWaitsForThePendingWrites() async {
        // GIVEN - 5 entries staged but not flushed, limit fits only 3
        let mb = 1024 * 1024
        cache.sizeLimit = mb * 3
        for index in 1...5 {
            cache["key\(index)"] = Data(repeating: UInt8(index), count: mb)
        }

        // WHEN the sweep runs without an explicit flush first
        await cache.sweep()

        // THEN the writes reached the disk before the sweep measured the size
        #expect(cache.totalCount <= 3)
        #expect(cache.totalSize <= mb * 3)
    }

    @Test func sweepReturnsUnderSustainedWriteTraffic() async {
        // GIVEN a steady stream of writes that never lets the staging area
        // drain. The keys are recycled so that the traffic can't grow the cache
        // without a bound for as long as the test runs.
        let cache = self.cache
        let traffic = Task.detached {
            var index = 0
            while !Task.isCancelled {
                cache["traffic\(index % trafficKeyCount)"] = blob
                index += 1
                await Task.yield()
            }
        }

        // WHEN
        await cache.sweep() // The writes must not starve the sweep

        // THEN
        traffic.cancel()
        _ = await traffic.value
        await cache.flush() // Drain what the traffic left behind
    }

    @Test func sweepRemovesTheLeastRecentlyUsedItems() async throws {
        // GIVEN four entries and a limit that fits two of them
        let mb = 1024 * 1024
        cache.sizeLimit = mb * 3 // The trim ratio takes it down to 2.1 MB
        for index in 1...4 {
            cache["key\(index)"] = Data(repeating: UInt8(index), count: mb)
        }
        await cache.flush()

        // The order the changes are written in isn't specified, so stamp the
        // access dates instead of relying on it: `key1` is the least recently
        // used, `key4` the most.
        let now = Date()
        for index in 1...4 {
            var url = try #require(cache.url(for: "key\(index)"))
            var values = URLResourceValues()
            values.contentAccessDate = now.addingTimeInterval(TimeInterval(index - 5) * 100)
            try url.setResourceValues(values)
        }

        // WHEN
        await cache.sweep()

        // THEN the two least recently used are the ones that go
        #expect(cache.containsData(for: "key4"))
        #expect(cache.containsData(for: "key3"))
        #expect(!cache.containsData(for: "key2"))
        #expect(!cache.containsData(for: "key1"))
    }

    @Test func sweepTrimsToTheTrimRatioAndNotToTheSizeLimit() async {
        // GIVEN 5 MB in a cache that goes down to 2 MB once it's over the limit
        let mb = 1024 * 1024
        cache.sizeLimit = mb * 4
        cache.trimRatio = 0.5
        for index in 1...5 {
            cache["key\(index)"] = Data(repeating: UInt8(index), count: mb)
        }
        await cache.flush()

        // WHEN
        await cache.sweep()

        // THEN it keeps removing past the point where it's back under the limit
        #expect(cache.totalSize <= mb * 2)
    }

    // MARK: Inspection

    @Test func containsData() async {
        // GIVEN
        cache["key"] = blob
        await cache.flush()

        // WHEN/THEN
        #expect(cache.containsData(for: "key"))
    }

    @Test func containsDataInStaging() {
        // GIVEN
        cache.withSuspendedIO {
            cache["key"] = blob

            // WHEN/THEN
            #expect(cache.containsData(for: "key"))
        }
    }

    @Test func containsDataAfterRemoval() async {
        // GIVEN
        cache["key"] = blob
        await cache.flush()

        cache.withSuspendedIO {
            cache["key"] = nil

            // WHEN/THEN
            #expect(!cache.containsData(for: "key"))
        }
    }

    @Test func totalCount() async {
        #expect(cache.totalCount == 0)

        cache["1"] = "1".data(using: .utf8)
        await cache.flush()

        #expect(cache.totalCount == 1)
    }

    @Test func totalSize() async {
        #expect(cache.totalSize == 0)

        cache["1"] = "1".data(using: .utf8)
        await cache.flush()

        #expect(cache.totalSize > 0)
    }

    @Test func totalAllocatedSize() async {
        #expect(cache.totalAllocatedSize == 0)

        cache["1"] = "1".data(using: .utf8)
        await cache.flush()

        // Depends on the file system.
        #expect(cache.totalAllocatedSize > 0)
    }

    // MARK: Resilience

    @Test func whenDirectoryDeletedCacheAutomaticallyRecreatesIt() async throws {
        cache["1"] = "2".data(using: .utf8)
        await cache.flush()

        try FileManager.default.removeItem(at: cache.path)

        cache["1"] = "2".data(using: .utf8)
        await cache.flush()

        let url = try #require(cache.url(for: "1"))
        let data = try Data(contentsOf: url)
        #expect(String(data: data, encoding: .utf8) == "2")
    }

    // MARK: Persistence

    @Test func flushedDataIsVisibleToANewInstanceAtTheSamePath() async throws {
        // GIVEN
        let name = UUID().uuidString
        let cache = try DataCache(name: name, filenameGenerator: { String($0.reversed()) })
        defer { try? FileManager.default.removeItem(at: cache.path) }
        cache["key"] = blob
        await cache.flush()

        // WHEN a separate instance opens the same directory
        let other = try DataCache(name: name, filenameGenerator: { String($0.reversed()) })

        // THEN
        #expect(other["key"] == blob)
        #expect(other.totalCount == 1)
    }

    // MARK: Default Filename Generator

    @Test func initWithPathUsingDefaultFilenameGenerator() async throws {
        let name = UUID().uuidString
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(name, isDirectory: true)
        let cache = try DataCache(path: path)
        defer { try? FileManager.default.removeItem(at: cache.path) }

        cache["http://example.com/image.png"] = blob
        await cache.flush()

        #expect(cache.containsData(for: "http://example.com/image.png"))
        #expect(cache.filename(for: "http://example.com/image.png") != nil)
    }

    // MARK: Invalid Keys

    @Test func cachedDataForEmptyKey() throws {
        let cache = try DataCache(name: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache.path) }
        #expect(cache.cachedData(for: "") == nil)
    }

    @Test func containsDataForEmptyKey() throws {
        let cache = try DataCache(name: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache.path) }
        #expect(!cache.containsData(for: ""))
    }

    @Test func urlForEmptyKey() throws {
        let cache = try DataCache(name: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache.path) }
        #expect(cache.url(for: "") == nil)
    }

    // MARK: Metadata

    @Test func scheduledSweepUpdatesMetadata() async throws {
        let expectation = TestExpectation()
        let cache = try DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) },
            sweepDelay: .milliseconds(0),
            onSweepCompleted: { expectation.fulfill() }
        )
        defer { try? FileManager.default.removeItem(at: cache.path) }
        await expectation.wait()

        let metadataURL = cache.path.appendingPathComponent(".data-cache-info")
        struct CacheMetadata: Codable { var lastSweepDate: Date? }
        let data = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(CacheMetadata.self, from: data)
        #expect(metadata.lastSweepDate != nil)
        _ = cache
    }

    @Test func initWithExistingMetadataSkipsSweep() async throws {
        let name = UUID().uuidString
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let path = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        struct CacheMetadata: Codable { var lastSweepDate: Date? }
        let metadata = CacheMetadata(lastSweepDate: Date())
        try JSONEncoder().encode(metadata).write(
            to: path.appendingPathComponent(".data-cache-info")
        )

        let cache = try DataCache(path: path, filenameGenerator: { String($0.reversed()) })
        defer { try? FileManager.default.removeItem(at: cache.path) }

        cache["key"] = blob
        await cache.flush()
        #expect(cache["key"] == blob)
    }

    @Test func scheduledSweepIsSkippedWhenDisabled() async throws {
        let cache = try DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) },
            sweepDelay: .milliseconds(100),
            onSweepCompleted: { Issue.record("the sweep ran with `isSweepEnabled` off") }
        )
        defer { try? FileManager.default.removeItem(at: cache.path) }
        cache.isSweepEnabled = false

        try await Task.sleep(for: .milliseconds(300))

        // THEN the sweep never ran, so it never stamped its metadata either
        let metadataURL = cache.path.appendingPathComponent(".data-cache-info")
        #expect(!FileManager.default.fileExists(atPath: metadataURL.path))
    }

    @Test func scheduledSweepRunsWhenTheLastOneIsOlderThanTheInterval() async throws {
        // GIVEN metadata from a sweep that predates `sweepInterval` (1800s)
        let name = UUID().uuidString
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        struct CacheMetadata: Codable { var lastSweepDate: Date? }
        let metadata = CacheMetadata(lastSweepDate: Date(timeIntervalSinceNow: -3600))
        try JSONEncoder().encode(metadata).write(
            to: path.appendingPathComponent(".data-cache-info")
        )

        // WHEN
        let expectation = TestExpectation()
        let cache = try DataCache(
            name: name,
            filenameGenerator: { String($0.reversed()) },
            sweepDelay: .milliseconds(0),
            onSweepCompleted: { expectation.fulfill() }
        )
        defer { try? FileManager.default.removeItem(at: cache.path) }

        // THEN the stale date doesn't hold the sweep back
        await expectation.wait(timeout: .seconds(5))
    }

    // MARK: Sweep Edge Cases

    @Test func sweepWhenSizeUnderLimit() async throws {
        let cache = try DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) }
        )
        defer { try? FileManager.default.removeItem(at: cache.path) }
        cache.sizeLimit = 1024 * 1024 * 100
        cache["a"] = Data(repeating: 1, count: 100)
        await cache.flush()

        await cache.sweep()
        #expect(cache.containsData(for: "a"))
    }

    @Test func sweepWhenEmpty() async throws {
        let cache = try DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) }
        )
        defer { try? FileManager.default.removeItem(at: cache.path) }
        await cache.sweep()
        #expect(cache.totalCount == 0)
    }

    // MARK: Large Data

    @Test func storeLargeData() async {
        // GIVEN - a 500 KB payload (well above typical image sizes used in other tests)
        let largeData = Data(repeating: 0xAB, count: 500_000)

        // WHEN
        cache["large-key"] = largeData
        await cache.flush()

        // THEN - data survives the flush and is retrieved intact
        let retrieved = cache.cachedData(for: "large-key")
        #expect(retrieved?.count == largeData.count)
    }

    @Test func storeLargeDataReplacedBySmallData() async {
        // GIVEN - write a large blob, then overwrite with a small blob
        let largeData = Data(repeating: 0xFF, count: 500_000)
        let smallData = Data(repeating: 0x01, count: 100)

        cache["key"] = largeData
        await cache.flush()

        cache["key"] = smallData
        await cache.flush()

        // THEN - the latest (small) payload wins
        let retrieved = cache.cachedData(for: "key")
        #expect(retrieved?.count == smallData.count)
    }

    // MARK: Store Data for Invalid Key

    @Test func storeDataForEmptyKeyIsNoOp() async throws {
        let cache = try DataCache(name: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache.path) }
        cache.storeData(blob!, for: "")
        await cache.flush()

        #expect(cache.totalCount == 0)
    }

}

extension DataCache {
    var contents: [URL] {
        return try! FileManager.default.contentsOfDirectory(at: self.path, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    }
}

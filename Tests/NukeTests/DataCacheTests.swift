// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Security
@testable import Nuke

private let blob = "123".data(using: .utf8)
private let otherBlob = "456".data(using: .utf8)

@Suite(.timeLimit(.minutes(5)))
struct DataCacheTests {
    private let cache: DataCache

    init() throws {
        cache = try DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) }
        )
    }

    // MARK: Init

    @Test func initWithName() throws {
        // Given
        let name = UUID().uuidString

        // When
        let cache = try DataCache(name: name, filenameGenerator: { $0 })

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

        // Then
        #expect(cache.path == path)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    // MARK: Default Key Encoder

    @Test func defaultKeyEncoder() throws {
        let cache = try DataCache(name: UUID().uuidString)
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

    @Test func getCachedDataHitFromStaging() async {
        // Given data that is only in the staging area
        cache.suspendIO()
        cache["key"] = blob

        // When/Then
        let data = await cache.cachedData(for: "key")
        #expect(data == blob)

        cache.resumeIO()
    }

    @Test func getCachedData() async {
        // Given
        cache["key"] = blob
        await cache.flush()

        // When/Then
        let data = await cache.cachedData(for: "key")
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

    @Test func flushWaitsForPendingWrites() async {
        // Given
        cache.suspendIO()
        cache["key1"] = blob
        cache["key2"] = otherBlob

        // When the I/O is resumed while a flush is pending
        async let pending: Void = cache.flush()
        cache.resumeIO()
        await pending

        // Then
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

    // MARK: Inspection

    @Test func containsData() async {
        // GIVEN
        cache["key"] = blob
        await cache.flush()

        // WHEN/THEN
        #expect(await cache.containsData(for: "key"))
    }

    @Test func containsDataInStaging() async {
        // GIVEN
        cache.suspendIO()
        cache["key"] = blob

        // WHEN/THEN
        #expect(await cache.containsData(for: "key"))

        cache.resumeIO()
    }

    @Test func containsDataAfterRemoval() async {
        // GIVEN
        cache["key"] = blob
        await cache.flush()
        cache.suspendIO()
        cache["key"] = nil

        // WHEN/THEN
        #expect(await !cache.containsData(for: "key"))

        cache.resumeIO()
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

    // MARK: Default Filename Generator

    @Test func initWithPathUsingDefaultFilenameGenerator() async throws {
        let name = UUID().uuidString
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(name, isDirectory: true)
        let cache = try DataCache(path: path)

        cache["http://example.com/image.png"] = blob
        await cache.flush()

        #expect(await cache.containsData(for: "http://example.com/image.png"))
        #expect(cache.filename(for: "http://example.com/image.png") != nil)
    }

    // MARK: Invalid Keys

    @Test func cachedDataForEmptyKey() async throws {
        let cache = try DataCache(name: UUID().uuidString)
        #expect(await cache.cachedData(for: "") == nil)
    }

    @Test func containsDataForEmptyKey() async throws {
        let cache = try DataCache(name: UUID().uuidString)
        #expect(await !cache.containsData(for: ""))
    }

    @Test func urlForEmptyKey() throws {
        let cache = try DataCache(name: UUID().uuidString)
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

        cache["key"] = blob
        await cache.flush()
        #expect(cache["key"] == blob)
    }

    // MARK: Sweep Edge Cases

    @Test func sweepWhenSizeUnderLimit() async throws {
        let cache = try DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) }
        )
        cache.sizeLimit = 1024 * 1024 * 100
        cache["a"] = Data(repeating: 1, count: 100)
        await cache.flush()

        await cache.sweep()
        #expect(await cache.containsData(for: "a"))
    }

    @Test func sweepWhenEmpty() async throws {
        let cache = try DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) }
        )
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
        let retrieved = await cache.cachedData(for: "large-key")
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
        let retrieved = await cache.cachedData(for: "key")
        #expect(retrieved?.count == smallData.count)
    }

    // MARK: Store Data for Invalid Key

    @Test func storeDataForEmptyKeyIsNoOp() async throws {
        let cache = try DataCache(name: UUID().uuidString)
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

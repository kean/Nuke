// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Security
@testable import Nuke

private let blob = "123".data(using: .utf8)
private let otherBlob = "456".data(using: .utf8)

@Suite struct DataCacheTests {
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

    @Test func addAndFlush() {
        // Given
        cache.withSuspendedIO {
            cache["key"] = blob
        }

        // When
        cache.flush()

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

    @Test func replaceFlushed() {
        // Given
        cache["key"] = blob
        cache.flush()

        cache.withSuspendedIO {
            cache["key"] = otherBlob
            #expect(cache.contents.count == 1)
            // Test that before flush we still have the old blob on disk,
            // but new blob in staging
            #expect((try? Data(contentsOf: cache.contents.first!)) == blob)
            #expect(cache["key"] == otherBlob)
        }

        // Flush and test that data on disk was updated.
        cache.flush()
        #expect(cache.contents.count == 1)
        #expect((try? Data(contentsOf: cache.contents.first!)) == otherBlob)
        #expect(cache["key"] == otherBlob)
    }

    // MARK: Removal

    @Test func removeNonExistent() {
        cache["key"] = nil
        cache.flush()
    }

    // - Remove + write (new) staged -> remove from staging
    @Test func removeFromStaging() {
        cache.withSuspendedIO {
            cache["key"] = blob
            cache["key"] = nil
            #expect(cache["key"] == nil)
        }
        cache.flush()
        #expect(cache["key"] == nil)
    }

    // - Remove + write (new) staged -> remove from staging
    @Test func removeReplaced() {
        cache.withSuspendedIO {
            cache["key"] = blob
            cache["key"] = otherBlob
            cache["key"] = nil
        }
        cache.flush()
        #expect(cache["key"] == nil)
        #expect(cache.contents.count == 0)
    }

    // - Remove + write (replace) staged -> schedule removal
    @Test func removeReplacedFlushed() {
        cache["key"] = blob
        cache.flush()

        cache.withSuspendedIO {
            cache["key"] = otherBlob
            cache["key"] = nil
            #expect(cache["key"] == nil)
            #expect((try? Data(contentsOf: cache.contents.first!)) == blob)
        }

        cache.flush() // Should still perform deletion of "blob"
        #expect(cache.contents.count == 0)
    }

    // - Remove + flushed -> schedule removal
    @Test func removeFlushed() {
        // Given
        cache["key"] = blob
        cache.flush()

        cache.withSuspendedIO {
            cache["key"] = nil
            #expect(cache["key"] == nil)
            // Still have data in cache
            #expect(cache.contents.count == 1)
            #expect((try? Data(contentsOf: cache.contents.first!)) == blob)
        }
        cache.flush()

        #expect(cache["key"] == nil)

        // IO performed
        #expect(cache.contents.count == 0)
    }

    // - Remove + removal staged -> noop
    @Test func removeWhenRemovalAlreadyScheduled() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache["key"] = nil
        cache["key"] = nil
        cache.flush()

        // Then
        #expect(cache.contents.count == 0)
    }

    @Test func removeAndThenReplace() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache["key"] = nil
        cache["key"] = blob
        cache.flush()

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

    @Test func removeAllFlushed() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache.withSuspendedIO {
            cache.removeAll()
            #expect(cache["key"] == nil)
        }
    }

    @Test func removeAllFlushedAndFlush() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache.removeAll()
        cache.flush()

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
        // Given
        cache.flush() // Index is loaded

        cache.withSuspendedIO {
            // Given
            cache["key"] = blob

            // When/Then
            let data = cache.cachedData(for: "key")
            #expect(data == blob)
        }
    }

    @Test func getCachedData() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When/Then
        let data = cache.cachedData(for: "key")
        #expect(data == blob)
    }

    // MARK: Flush

    @Test func flush() {
        // Given
        cache.flushInterval = .seconds(20)
        cache["key"] = blob

        // When
        cache.flush()

        // Then
        #expect(cache.contents == [cache.url(for: "key")].compactMap { $0 })
    }

    @Test func flushForKey() {
        // Given
        cache.flushInterval = .seconds(20)
        cache["key"] = blob

        // When
        cache.flush(for: "key")

        // Then
        #expect(cache.contents == [cache.url(for: "key")].compactMap { $0 })
    }

    @Test func flushForKey2() {
        // Given
        cache.flushInterval = .seconds(20)
        cache["key1"] = blob
        cache["key2"] = blob

        // When
        cache.flush(for: "key1")

        // Then only flushes content for the specific key
        #expect(cache.contents == [cache.url(for: "key1")].compactMap { $0 })
    }

    // MARK: Sweep

    @Test func sweep() {
        // GIVEN
        let mb = 1024 * 1024 // allocated size is usually about 4 KB on APFS, so use 1 MB just to be sure
        cache.sizeLimit = mb * 3
        cache["key1"] = Data(repeating: 1, count: mb)
        cache["key2"] = Data(repeating: 1, count: mb)
        cache["key3"] = Data(repeating: 1, count: mb)
        cache["key4"] = Data(repeating: 1, count: mb)
        cache.flush()

        // WHEN
        cache.sweep()

        // THEN
        #expect(cache.totalSize == mb * 2)
    }

    @Test func sweepReducesTotalCount() {
        // GIVEN - 5 entries, limit fits only 3
        let mb = 1024 * 1024
        cache.sizeLimit = mb * 3
        for i in 1...5 {
            cache["key\(i)"] = Data(repeating: UInt8(i), count: mb)
        }
        cache.flush()

        // WHEN
        cache.sweep()

        // THEN - at most 3 MB worth of entries remain
        #expect(cache.totalCount <= 3)
        #expect(cache.totalSize <= mb * 3)
    }

    @Test func sweepIsNoOpWhenUnderLimit() {
        // GIVEN - total size well under the limit
        let mb = 1024 * 1024
        cache.sizeLimit = mb * 10
        cache["small1"] = Data(repeating: 1, count: mb)
        cache["small2"] = Data(repeating: 2, count: mb)
        cache.flush()

        let countBefore = cache.totalCount

        // WHEN
        cache.sweep()

        // THEN - nothing is removed
        #expect(cache.totalCount == countBefore)
    }

    // MARK: Inspection

    @Test func containsData() {
        // GIVEN
        cache["key"] = blob
        cache.flush(for: "key")

        // WHEN/THEN
        #expect(cache.containsData(for: "key"))
    }

    @Test func containsDataInStaging() {
        // GIVEN
        cache.flushInterval = .seconds(20)
        cache["key"] = blob

        // WHEN/THEN
        #expect(cache.containsData(for: "key"))
    }

    @Test func containsDataAfterRemoval() {
        // GIVEN
        cache.flushInterval = .seconds(20)
        cache["key"] = blob
        cache.flush(for: "key")
        cache["key"] = nil

        // WHEN/THEN
        #expect(!cache.containsData(for: "key"))
    }

    @Test func totalCount() {
        #expect(cache.totalCount == 0)

        cache["1"] = "1".data(using: .utf8)
        cache.flush()

        #expect(cache.totalCount == 1)
    }

    @Test func totalSize() {
        #expect(cache.totalSize == 0)

        cache["1"] = "1".data(using: .utf8)
        cache.flush()

        #expect(cache.totalSize > 0)
    }

    @Test func totalAllocatedSize() {
        #expect(cache.totalAllocatedSize == 0)

        cache["1"] = "1".data(using: .utf8)
        cache.flush()

        // Depends on the file system.
        #expect(cache.totalAllocatedSize > 0)
    }

    // MARK: Resilience

    @Test func whenDirectoryDeletedCacheAutomaticallyRecreatesIt() throws {
        cache["1"] = "2".data(using: .utf8)
        cache.flush()

        try FileManager.default.removeItem(at: cache.path)

        cache["1"] = "2".data(using: .utf8)
        cache.flush()

        let url = try #require(cache.url(for: "1"))
        let data = try Data(contentsOf: url)
        #expect(String(data: data, encoding: .utf8) == "2")
    }

    // MARK: Default Filename Generator

    @Test func initWithPathUsingDefaultFilenameGenerator() throws {
        let name = UUID().uuidString
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(name, isDirectory: true)
        let cache = try DataCache(path: path)

        cache["http://example.com/image.png"] = blob
        cache.flush()

        #expect(cache.containsData(for: "http://example.com/image.png"))
        #expect(cache.filename(for: "http://example.com/image.png") != nil)
    }

    // MARK: Invalid Keys

    @Test func cachedDataForEmptyKey() throws {
        let cache = try DataCache(name: UUID().uuidString)
        #expect(cache.cachedData(for: "") == nil)
    }

    @Test func containsDataForEmptyKey() throws {
        let cache = try DataCache(name: UUID().uuidString)
        #expect(!cache.containsData(for: ""))
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

    @Test func initWithExistingMetadataSkipsSweep() throws {
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
        cache.flush()
        #expect(cache["key"] == blob)
    }

    // MARK: Sweep Edge Cases

    @Test func sweepWhenSizeUnderLimit() throws {
        let cache = try DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) }
        )
        cache.sizeLimit = 1024 * 1024 * 100
        cache["a"] = Data(repeating: 1, count: 100)
        cache.flush()

        cache.sweep()
        #expect(cache.containsData(for: "a"))
    }

    @Test func sweepWhenEmpty() throws {
        let cache = try DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) }
        )
        cache.sweep()
        #expect(cache.totalCount == 0)
    }

    // MARK: Large Data

    @Test func storeLargeData() {
        // GIVEN - a 500 KB payload (well above typical image sizes used in other tests)
        let largeData = Data(repeating: 0xAB, count: 500_000)

        // WHEN
        cache["large-key"] = largeData
        cache.flush()

        // THEN - data survives the flush and is retrieved intact
        let retrieved = cache.cachedData(for: "large-key")
        #expect(retrieved?.count == largeData.count)
    }

    @Test func storeLargeDataReplacedBySmallData() {
        // GIVEN - write a large blob, then overwrite with a small blob
        let largeData = Data(repeating: 0xFF, count: 500_000)
        let smallData = Data(repeating: 0x01, count: 100)

        cache["key"] = largeData
        cache.flush()

        cache["key"] = smallData
        cache.flush()

        // THEN - the latest (small) payload wins
        let retrieved = cache.cachedData(for: "key")
        #expect(retrieved?.count == smallData.count)
    }

    // MARK: Store Data for Invalid Key

    @Test func storeDataForEmptyKeyIsNoOp() throws {
        let cache = try DataCache(name: UUID().uuidString)
        cache.storeData(blob!, for: "")
        cache.flush()

        #expect(cache.totalCount == 0)
    }

}

extension DataCache {
    var contents: [URL] {
        return try! FileManager.default.contentsOfDirectory(at: self.path, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    }

    func withSuspendedIO(_ closure: () -> Void) {
        queue.suspend()
        closure()
        queue.resume()
    }
}

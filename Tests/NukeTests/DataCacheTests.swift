// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
import Security
@testable import Nuke

let blob = "123".data(using: .utf8)
let otherBlob = "456".data(using: .utf8)

class DataCacheTests: XCTestCase {
    var cache: DataCache!

    override func setUp() {
        super.setUp()

        // Make sure that file names are different from the keys so that we
        // could know for sure that keyEncoder works as expected.
        cache = try! DataCache(
            name: UUID().uuidString,
            filenameGenerator: { String($0.reversed()) }
        )
    }

    override func tearDown() {
        super.tearDown()

        try? FileManager.default.removeItem(at: cache.path)
    }

    // MARK: Init

    func testInitWithName() {
        // Given
        let name = UUID().uuidString

        // When
        let cache = try! DataCache(name: name, filenameGenerator: { $0 })

        // Then
        XCTAssertEqual(cache.path.lastPathComponent, name)
        XCTAssertNotNil(FileManager.default.fileExists(atPath: cache.path.absoluteString))
    }

    func testInitWithPath() {
        // Given
        let name = UUID().uuidString
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(name)

        // When
        let cache = try! DataCache(path: path, filenameGenerator: { $0 })

        // Then
        XCTAssertEqual(cache.path, path)
        XCTAssertNotNil(FileManager.default.fileExists(atPath: path.absoluteString))
    }

    // MARK: Default Key Encoder

    func testDefaultKeyEncoder() {
        let cache = try! DataCache(name: UUID().uuidString)
        let filename = cache.filename(for: "http://test.com")
        XCTAssertEqual(filename, "8b408a0c7163fdfff06ced3e80d7d2b3acd9db900905c4783c28295b8c996165")
    }

    func testSHA256() {
        XCTAssertEqual("http://test.com".sha256, "8b408a0c7163fdfff06ced3e80d7d2b3acd9db900905c4783c28295b8c996165")
    }

    // MARK: Add

    func testAdd() {
        cache.withSuspendedIO {
            // When
            cache["key"] = blob

            // Then
            XCTAssertEqual(cache["key"], blob)
        }
    }

    func testWhenAddContentNotFlushedImmediately() {
        cache.withSuspendedIO {
            // When
            cache["key"] = blob

            // Then
            XCTAssertEqual(cache.contents.count, 0)
        }
    }

    func testAddAndFlush() {
        // Given
        cache.withSuspendedIO {
            cache["key"] = blob
        }

        // When
        cache.flush()

        // Then
        XCTAssertEqual(cache.contents.count, 1)
        XCTAssertEqual(cache["key"], blob)
        XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
    }

    func testReplace() {
        cache.withSuspendedIO {
            // Given
            cache["key"] = blob

            // When
            cache["key"] = otherBlob

            // Then
            XCTAssertEqual(cache["key"], otherBlob)
        }
    }

    func testReplaceFlushed() {
        // Given
        cache["key"] = blob
        cache.flush()

        cache.withSuspendedIO {
            cache["key"] = otherBlob
            XCTAssertEqual(cache.contents.count, 1)
            // Test that before flush we still have the old blob on disk,
            // but new blob in staging
            XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
            XCTAssertEqual(cache["key"], otherBlob)
        }

        // Flush and test that data on disk was updated.
        cache.flush()
        XCTAssertEqual(cache.contents.count, 1)
        XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), otherBlob)
        XCTAssertEqual(cache["key"], otherBlob)
    }

    // MARK: Removal

    func testRemoveNonExistent() {
        cache["key"] = nil
        cache.flush()
    }

    // - Remove + write (new) staged -> remove from staging
    func testRemoveFromStaging() {
        cache.withSuspendedIO {
            cache["key"] = blob
            cache["key"] = nil
            XCTAssertNil(cache["key"])
        }
        cache.flush()
        XCTAssertNil(cache["key"])
    }

    // - Remove + write (new) staged -> remove from staging
    func testRemoveReplaced() {
        cache.withSuspendedIO {
            cache["key"] = blob
            cache["key"] = otherBlob
            cache["key"] = nil
        }
        cache.flush()
        XCTAssertNil(cache["key"])
        XCTAssertEqual(cache.contents.count, 0)
    }

    // - Remove + write (replace) staged -> schedule removal
    func testRemoveReplacedFlushed() {
        cache["key"] = blob
        cache.flush()

        cache.withSuspendedIO {
            cache["key"] = otherBlob
            cache["key"] = nil
            XCTAssertNil(cache["key"])
            XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
        }

        cache.flush() // Should still perform deletion of "blob"
        XCTAssertEqual(cache.contents.count, 0)
    }

    // - Remove + flushed -> schedule removal
    func testRemoveFlushed() {
        // Given
        cache["key"] = blob
        cache.flush()

        cache.withSuspendedIO {
            cache["key"] = nil
            XCTAssertNil(cache["key"])
            // Still have data in cache
            XCTAssertEqual(cache.contents.count, 1)
            XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
        }
        cache.flush()

        XCTAssertNil(cache["key"])

        // IO performed
        XCTAssertEqual(cache.contents.count, 0)
    }

    // - Remove + removal staged -> noop
    func testRemoveWhenRemovalAlreadyScheduled() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache["key"] = nil
        cache["key"] = nil
        cache.flush()

        // Then
        XCTAssertEqual(cache.contents.count, 0)
    }

    func testRemoveAndThenReplace() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache["key"] = nil
        cache["key"] = blob
        cache.flush()

        // Then
        XCTAssertEqual(cache["key"], blob)
        XCTAssertEqual(cache.contents.count, 1)
        XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
    }

    // MARK: Remove All

    func testRemoveAll() {
        cache.withSuspendedIO {
            // Given
            cache["key"] = blob

            // When
            cache.removeAll()

            // Then
            XCTAssertNil(cache["key"])
        }
    }

    func testRemoveAllFlushed() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache.withSuspendedIO {
            cache.removeAll()
            XCTAssertNil(cache["key"])
        }
    }

    func testRemoveAllFlushedAndFlush() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When
        cache.removeAll()
        cache.flush()

        // Then
        XCTAssertNil(cache["key"])
        XCTAssertEqual(cache.contents.count, 0)
    }

    func testRemoveAllAndAdd() {
        // Given
        cache.withSuspendedIO {
            cache["key"] = blob

            // When
            cache.removeAll()
            cache["key"] = blob

            // Then
            XCTAssertEqual(cache["key"], blob)
        }
    }

    func testRemoveAllTwice() {
        // Given
        cache.withSuspendedIO {
            cache["key"] = blob

            // When
            cache.removeAll()
            cache["key"] = blob
            cache.removeAll()

            // Then
            XCTAssertNil(cache["key"])
        }
    }

    // MARK: DataCaching

    func testGetCachedDataHitFromStaging() {
        // Given
        cache.flush() // Index is loaded

        cache.withSuspendedIO {
            // Given
            cache["key"] = blob

            // When/Then
            let data = cache.cachedData(for: "key")
            XCTAssertEqual(data, blob)
        }
    }

    func testGetCachedData() {
        // Given
        cache["key"] = blob
        cache.flush()

        // When/Then
        let data = cache.cachedData(for: "key")
        XCTAssertEqual(data, blob)
    }

    // MARK: Flush

    func testFlush() {
        // Given
        cache.flushInterval = .seconds(20)
        cache["key"] = blob

        // When
        cache.flush()

        // Then
        XCTAssertEqual(cache.contents, [cache.url(for: "key")].compactMap { $0 })
    }

    func testFlushForKey() {
        // Given
        cache.flushInterval = .seconds(20)
        cache["key"] = blob

        // When
        cache.flush(for: "key")

        // Then
        XCTAssertEqual(cache.contents, [cache.url(for: "key")].compactMap { $0 })
    }

    func testFlushForKey2() {
        // Given
        cache.flushInterval = .seconds(20)
        cache["key1"] = blob
        cache["key2"] = blob

        // When
        cache.flush(for: "key1")

        // Then only flushes content for the specific key
        XCTAssertEqual(cache.contents, [cache.url(for: "key1")].compactMap { $0 })
    }

    // MARK: Sweep

    func testSweep() {
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
        XCTAssertEqual(cache.totalSize, mb * 2)
    }

    // MARK: Inspection

    func testContainsData() {
        // GIVEN
        cache["key"] = blob
        cache.flush(for: "key")

        // WHEN/THEN
        XCTAssertTrue(cache.containsData(for: "key"))
    }

    func testContainsDataInStaging() {
        // GIVEN
        cache.flushInterval = .seconds(20)
        cache["key"] = blob

        // WHEN/THEN
        XCTAssertTrue(cache.containsData(for: "key"))
    }

    func testContainsDataAfterRemoval() {
        // GIVEN
        cache.flushInterval = .seconds(20)
        cache["key"] = blob
        cache.flush(for: "key")
        cache["key"] = nil

        // WHEN/THEN
        XCTAssertFalse(cache.containsData(for: "key"))
    }

    func testTotalCount() {
        XCTAssertEqual(cache.totalCount, 0)

        cache["1"] = "1".data(using: .utf8)
        cache.flush()

        XCTAssertEqual(cache.totalCount, 1)
    }

    func testTotalSize() {
        XCTAssertEqual(cache.totalSize, 0)

        cache["1"] = "1".data(using: .utf8)
        cache.flush()

        XCTAssertTrue(cache.totalSize > 0)
    }

    func testTotalAllocatedSize() {
        XCTAssertEqual(cache.totalAllocatedSize, 0)

        cache["1"] = "1".data(using: .utf8)
        cache.flush()

        // Depends on the file system.
        XCTAssertTrue(cache.totalAllocatedSize > 0)
    }

    // MARK: Resilience

    func testWhenDirectoryDeletedCacheAutomaticallyRecreatesIt() {
        cache["1"] = "2".data(using: .utf8)
        cache.flush()

        do {
            try FileManager.default.removeItem(at: cache.path)
        } catch {
            XCTFail("Fail to remove cache directory")
        }

        cache["1"] = "2".data(using: .utf8)
        cache.flush()

        do {
            guard let url = cache.url(for: "1") else {
                return XCTFail("Failed to create URL")
            }
            let data = try Data(contentsOf: url)
            XCTAssertEqual(String(data: data, encoding: .utf8), "2")
        } catch {
            XCTFail("Failed to read data")
        }
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

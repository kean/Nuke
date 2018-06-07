// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

let blob = "123".data(using: .utf8)
let otherBlob = "456".data(using: .utf8)

class DataCacheTests: XCTestCase {
    var cache: DataCache!

    override func setUp() {
        cache = try! DataCache(name: UUID().uuidString)
        // Make sure that file names are different from the keys so that we
        // could know for sure that keyEncoder works as expected.
        cache._keyEncoder = { String($0.reversed()) }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache.path)
    }

    // MARK: Add

    func testAdd() {
        cache._test_withSuspendedIO {
            // When
            cache["key"] = blob

            // Then
            XCTAssertEqual(cache["key"], blob)
        }
    }

    func testWhenAddContentNotFlushedImmediately() {
        cache._test_withSuspendedIO {
            // When
            cache["key"] = blob

            // Then
            XCTAssertEqual(cache.contents.count, 0)
        }
    }

    func testAddAndFlush() {
        // Given
        cache._test_withSuspendedIO {
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
        cache._test_withSuspendedIO {
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

        cache._test_withSuspendedIO {
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

    // - Remove + write (new) staged -> remove form staging
    func testRemoveFromStaging() {
        cache._test_withSuspendedIO {
            cache["key"] = blob
            cache["key"] = nil
            XCTAssertNil(cache["key"])
        }
        cache.flush()
        XCTAssertNil(cache["key"])
    }

    // Same as:
    // - Remove + write (new) staged -> remove form staging
    func testRemoveReplaced() {
        cache._test_withSuspendedIO {
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

        cache._test_withSuspendedIO {
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

        cache._test_withSuspendedIO {
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

    func testThatRemoveAllWorks() {
        // Given
        cache["key"] = blob
        cache["key2"] = otherBlob
        cache.flush()

        // When
        cache._test_withSuspendedIO {
            cache.removeAll()
        }

        // Then
        cache.flush()
        XCTAssertNil(cache["key"])
        XCTAssertNil(cache["key2"])
        XCTAssertEqual(cache.contents.count, 0)
    }

    // MARK: Flush

    func testFlush() {
        // Given
        cache._test_withSuspendedIO {
            cache["key"] = blob
        }

        // When
        cache.flush()

        // Then
        XCTAssertEqual(cache.contents.count, 1)
    }

    // MARK: Index

    func testThatIndexIsLoaded() {
        XCTAssertNil(cache["key"])
        cache["key"] = blob
        XCTAssertNotNil(cache["key"])

        cache.flush()

        let cache2 = try! DataCache(path: cache.path)
        cache2._keyEncoder = cache._keyEncoder // keyEncoder not needed for index loading
        cache2._test_waitUntilIndexIsFullyLoaded()

        XCTAssertEqual(cache2["key"], cache["key"])
        XCTAssertEqual(cache2.totalSize, cache.totalSize)
        XCTAssertEqual(cache2.totalAllocatedSize, cache.totalAllocatedSize)
        XCTAssertEqual(cache2.totalCount, cache.totalCount)
    }

    // MARK: Inspection

    func testThatInspectionMethodsWork() {
        cache.inspect { XCTAssertEqual($0.count, 0) }
        XCTAssertEqual(cache.totalCount, 0)
        XCTAssertEqual(cache.totalSize, 0)

        let data = "123".data(using: .utf8)!

        cache._test_withSuspendedIO {

            cache["key"] = data

            cache.inspect {
                XCTAssertEqual($0.count, 1)
                XCTAssertNotNil($0[cache.filename(for: "key")!])
            }
            XCTAssertEqual(cache.totalCount, 1)
            XCTAssertEqual(cache.totalSize, data.count)
            XCTAssertEqual(cache.totalAllocatedSize, data.count)
        }

        cache.flush()

        // Size updated to allocated size.
        XCTAssertEqual(cache.totalSize, data.count)
        XCTAssertTrue(cache.totalAllocatedSize > cache.totalSize)
    }

    // MARK: Sweep

    func testSweep() {
        // Given
        cache = try! DataCache(path: cache.path)
        cache.countLimit = 4 // we test count limit here
        cache.trimRatio = 0.5 // 1 item should remaing after trim
        cache.sizeLimit = Int.max

        let keys = (0..<4).map { "\($0)" }

        keys.forEach {
            usleep(100) // make sure accessDate is different for each entry
            cache[$0] = "123".data(using: .utf8)
        }

        cache.flush() // Write to disk

        // When
        cache.sweep()
        cache.flush()

        // Then
        XCTAssertNil(cache[keys[0]])
        XCTAssertNil(cache[keys[1]])
        XCTAssertNotNil(cache[keys[2]])
        XCTAssertNotNil(cache[keys[3]])
    }

    // MARK: Intricacies

    func testThatAccessDateIsUpdatedOnRead() {
        cache._test_withSuspendedIO {
            // Given
            cache["1"] = "1".data(using: .utf8)

            // When

            // first access
            let _ = cache["1"]
            let date1 = cache.inspect {
                $0[cache.filename(for: "1")!]?.accessDate
            }

            usleep(100)

            // second access
            let _ = cache["1"]
            let date2 = cache.inspect {
                $0[cache.filename(for: "1")!]?.accessDate
            }

            // Then
            XCTAssertNotNil(date1)
            XCTAssertNotNil(date2)
            XCTAssertTrue(date1! < date2!)
        }
    }
}

extension DataCache {
    var contents: [URL] {
        return try! FileManager.default.contentsOfDirectory(at: self.path, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    }
}

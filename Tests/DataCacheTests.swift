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
        // To make sure that we use different strings for file names
        cache._keyEncoder = { String($0.reversed()) }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache.path)
    }

    // MARK: Addition

    func testAdd() {
        cache._test_withSuspendedIO {
            cache["key"] = blob
            XCTAssertEqual(cache["key"], blob)
            XCTAssertEqual(cache.contents.count, 0)
        }
    }

    func testAddAndFlush() {
        cache._test_withSuspendedIO {
            cache["key"] = blob
            XCTAssertEqual(cache.contents.count, 0)
        }
        cache.flush()
        XCTAssertEqual(cache.contents.count, 1)
        XCTAssertEqual(cache["key"], blob)
        XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
    }

    func testReplace() {
        cache._test_withSuspendedIO {
            cache["key"] = blob
            cache["key"] = otherBlob
            XCTAssertEqual(cache["key"], otherBlob)
            XCTAssertEqual(cache.contents.count, 0)
        }
    }

    func testReplaceFlushed() {
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
        cache["key"] = blob
        cache.flush()

        cache["key"] = nil
        cache["key"] = nil

        cache.flush()
        XCTAssertEqual(cache.contents.count, 0)
    }

    func testRemoveAndThenReplace() {
        cache["key"] = blob
        cache.flush()

        cache["key"] = nil
        cache["key"] = blob
        cache.flush()

        XCTAssertEqual(cache["key"], blob)
        XCTAssertEqual(cache.contents.count, 1)
        XCTAssertEqual(try? Data(contentsOf: cache.contents.first!), blob)
    }

    func testThatRemoveAllWorks() {
        cache["key"] = blob
        cache["key2"] = otherBlob
        cache.flush()

        XCTAssertEqual(cache["key"], blob)
        XCTAssertEqual(cache["key2"], otherBlob)

        cache._test_withSuspendedIO {
            cache.removeAll()
            XCTAssertEqual(cache.contents.count, 2)
        }

        cache.flush()
        XCTAssertNil(cache["key"])
        XCTAssertNil(cache["key2"])
        XCTAssertEqual(cache.contents.count, 0)
    }

    // MARK: Flush

    func testFlush() {
        cache._test_withSuspendedIO {
            XCTAssertEqual(cache.contents.count, 0)
            cache["key"] = blob
            XCTAssertEqual(cache.contents.count, 0)
        }
        cache.flush()
        XCTAssertEqual(cache.contents.count, 1)
    }

    // MARK: Index

//    func testThatIndexIsLoaded() {
//        XCTAssertNil(cache["key"])
//        cache["key"] = blob
//        XCTAssertNotNil(cache["key"])
//        cache.flush()
//
//        let cache2 = try! DataCache(path: cache.path)
//        cache2._keyEncoder = cache._keyEncoder
//
//        // DataCache guarantees that async data call will be executed after
//        // index is oaded, this is not true for synchronous methods.
//        expect { fulfil in
//            _ = cache2.data(for: "key") {
//                XCTAssertEqual($0, self.cache["key"])
//                fulfil()
//            }
//        }
//        wait()
//
//        XCTAssertEqual(cache2["key"], cache["key"])
//        XCTAssertEqual(cache2.totalSize, cache.totalSize)
//        XCTAssertEqual(cache2.totalAllocatedSize, cache.totalAllocatedSize)
//        XCTAssertEqual(cache2.totalCount, cache.totalCount)
//    }


    // MARK: Inspection

//    func testThatInspectionMethodsWork() {
//        cache.inspect { XCTAssertEqual($0.count, 0) }
//        XCTAssertEqual(cache.totalCount, 0)
//        XCTAssertEqual(cache.totalSize, 0)
//
//        let data = "123".data(using: .utf8)!
//
//        cache._test_withSuspendedIO {
//
//            cache["key"] = data
//
//            cache.inspect {
//                XCTAssertEqual($0.count, 1)
//                XCTAssertNotNil($0[cache.filename(for: "key")!])
//            }
//            XCTAssertEqual(cache.totalCount, 1)
//            XCTAssertEqual(cache.totalSize, data.count)
//            XCTAssertEqual(cache.totalAllocatedSize, data.count)
//        }
//
//        cache.flush()
//
//        // Size updated to allocated size.
//        XCTAssertEqual(cache.totalSize, data.count)
//        XCTAssertTrue(cache.totalAllocatedSize > cache.totalSize)
//    }

    // MARK: Sweep

    func testSweep() {
        var lru = CacheAlgorithmLRU()
        lru.countLimit = 4 // we test count limit here
        lru.trimRatio = 0.5 // 1 item should remaing after trim
        lru.sizeLimit = Int.max

        cache = try! DataCache(path: cache.path, algorithm: lru)

        let keys = (0..<4).map { "\($0)" }

        keys.forEach {
            usleep(100) // make sure accessDate is different for each entry
            cache[$0] = "123".data(using: .utf8)
        }

        // Flush entries to disk
        cache.flush()

        // Cleanup and flush changes
        cache.sweep()
        cache.flush()

        XCTAssertNil(cache[keys[0]])
        XCTAssertNil(cache[keys[1]])
        XCTAssertNotNil(cache[keys[2]])
        XCTAssertNotNil(cache[keys[3]])
    }

    // MARK: Intricacies

    func testThatAccessDateIsUpdatedOnRead() {
        cache._test_withSuspendedIO {
            cache["1"] = "1".data(using: .utf8)

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

            XCTAssertNotNil(date1)
            XCTAssertNotNil(date2)
            XCTAssertTrue(date1! < date2!)
        }
    }
}

class DataCacheAlgorithmTests: XCTestCase {
    func testThatLeastRecentlyItemsAreRemovedFirst() {
        let now = Date()

        let items = [
            makeItem(accessDate: now.addingTimeInterval(-10)),
            makeItem(accessDate: now.addingTimeInterval(-20)),
            makeItem(accessDate: now.addingTimeInterval(-30)),
            makeItem(accessDate: now.addingTimeInterval(-40))
        ]

        var lru = CacheAlgorithmLRU()
        lru.countLimit = 4 // we test count limit here
        lru.sizeLimit = Int.max
        lru.trimRatio = 0.5 // 1 item should remaing after trim

        test("") {
            let discarded = lru.discarded(items: items)
            XCTAssertEqual(discarded.count, 2)
            XCTAssertTrue(discarded.contains { $0 === items[3] })
            XCTAssertTrue(discarded.contains { $0 === items[2] })
        }

        test("") {
            // Reverse items and test that LRU still works
            let reversed = Array(items.reversed())
            let discarded = lru.discarded(items: items)
            XCTAssertEqual(discarded.count, 2)
            XCTAssertTrue(discarded.contains { $0 === reversed[0] })
            XCTAssertTrue(discarded.contains { $0 === reversed[1] })
        }
    }

    func testThatSizeLimitWorks() {
        let now = Date()

        let items = [
            makeItem(accessDate: now.addingTimeInterval(-10)),
            makeItem(accessDate: now.addingTimeInterval(-20)),
            makeItem(accessDate: now.addingTimeInterval(-30)),
            makeItem(accessDate: now.addingTimeInterval(-40))
        ]

        var lru = CacheAlgorithmLRU()
        lru.countLimit = 4 // we test count limit here
        lru.sizeLimit = Int.max
        lru.trimRatio = 0.5 // 1 item should remaing after trim

        test("") {
            let discarded = lru.discarded(items: items)
            XCTAssertEqual(discarded.count, 2)
            XCTAssertTrue(discarded.contains { $0 === items[3] })
            XCTAssertTrue(discarded.contains { $0 === items[2] })
        }
    }

    func makeItem(accessDate: Date) -> DataCache.Entry {
        let cache = try! DataCache(name: UUID().uuidString)
        let filename = cache.filename(for: "\(arc4random())")!
        let entry = DataCache.Entry(filename: filename, payload: .saved(URL(string: "file://\(filename.raw)")!))
        entry.accessDate = accessDate
        entry.totalFileAllocatedSize = 1
        return entry
    }
}

extension DataCache {
    var contents: [URL] {
        return try! FileManager.default.contentsOfDirectory(at: self.path, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    }
}


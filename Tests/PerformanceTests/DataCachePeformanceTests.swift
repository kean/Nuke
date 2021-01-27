// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class DataCachePeformanceTests: XCTestCase {
    var cache: DataCache!

    override func setUp() {
        cache = try! DataCache(name: UUID().uuidString)
        _ = cache["key"] // Wait till index is loaded.
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache.path)
    }

    func testReadFlushedPerformance() {
        for idx in 0..<1000 {
            cache["\(idx)"] = Data(repeating: 1, count: 256 * 1024)
        }
        cache.flush()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        measure {
            for idx in 0..<1000 {
                queue.addOperation {
                    _ = self.cache["\(idx)"]
                }
            }
            queue.waitUntilAllOperationsAreFinished()
        }
    }
}

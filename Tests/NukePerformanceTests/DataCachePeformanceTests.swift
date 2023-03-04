// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class DataCachePeformanceTests: XCTestCase {
    var cache: DataCache!
    var count = 1000

    override func setUp() {
        super.setUp()

        cache = try! DataCache(name: UUID().uuidString)
        _ = cache["key"] // Wait till index is loaded.
    }

    override func tearDown() {
        super.tearDown()

        try? FileManager.default.removeItem(at: cache.path)
    }

    func testReadFlushedPerformance() {
        populate()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        measure {
            for idx in 0..<count {
                queue.addOperation {
                    _ = self.cache["\(idx)"]
                }
            }
            queue.waitUntilAllOperationsAreFinished()
        }
    }

    func testReadFlushedPerformanceSync() {
        populate()

        measure {
            for idx in 0..<count {
                _ = self.cache["\(idx)"]
            }
        }
    }

    func testReadFlushedPerformanceWithCompression() {
        cache.isCompressionEnabled = true
        count = 100

        populate()

        measure {
            for idx in 0..<count {
                _ = self.cache["\(idx)"]
            }
        }
    }

    func populate() {
        for idx in 0..<count {
            cache["\(idx)"] = generateRandomData()
        }
        cache.flush()
    }
}

private func generateRandomData(count: Int = 256 * 1024) -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    assert(status == errSecSuccess)
    return Data(bytes)
}

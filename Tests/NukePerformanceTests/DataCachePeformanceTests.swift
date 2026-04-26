// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Security
import Nuke

@Suite(.serialized)
@MainActor
final class DataCachePeformanceTests {
    let cache: DataCache
    let count = 1000

    init() throws {
        cache = try DataCache(name: UUID().uuidString)
        _ = cache["key"] // Wait till index is loaded.
    }

    deinit {
        try? FileManager.default.removeItem(at: cache.path)
    }

    // MARK: - Write

    @Test
    func writeWithFlush() {
        let data = Array(0..<count).map { _ in generateRandomData() }

        measure {
            for index in data.indices {
                cache["\(index)"] = data[index]
            }
            cache.flush()
        }
    }

    @Test
    func writeWithFlushIndividual() {
        let data = Array(0..<200).map { _ in generateRandomData() }

        measure {
            for index in data.indices {
                let key = "\(index)"
                cache[key] = data[index]
                cache.flush(for: key)
            }
        }
    }

    @Test
    func writeWithoutFlush() {
        let data = Array(0..<count).map { _ in generateRandomData() }

        measure {
            for index in data.indices {
                cache["\(index)"] = data[index]
            }
        }
    }

    // MARK: - Read

    @Test
    func readFlushedPerformance() {
        populate()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        measure { [cache] in
            for idx in 0..<count {
                queue.addOperation {
                    _ = cache["\(idx)"]
                }
            }
            queue.waitUntilAllOperationsAreFinished()
        }
    }

    @Test
    func readFlushedPerformanceSync() {
        populate()

        measure {
            for idx in 0..<count {
                _ = self.cache["\(idx)"]
            }
        }
    }

    // MARK: - Helpers

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

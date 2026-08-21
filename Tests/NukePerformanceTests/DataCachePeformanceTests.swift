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
    func writeWithFlush() async {
        let data = Array(0..<count).map { _ in generateRandomData() }

        await measure { [cache] in
            for index in data.indices {
                cache["\(index)"] = data[index]
            }
            await cache.flush()
        }
    }

    @Test
    func writeWithFlushIndividual() async {
        let data = Array(0..<200).map { _ in generateRandomData() }

        await measure { [cache] in
            for index in data.indices {
                cache["\(index)"] = data[index]
                await cache.flush()
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
    func readFlushedPerformance() async {
        await populate()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        measure { [cache, count] in
            for idx in 0..<count {
                queue.addOperation {
                    _ = cache["\(idx)"]
                }
            }
            queue.waitUntilAllOperationsAreFinished()
        }
    }

    @Test
    func readFlushedPerformanceSync() async {
        await populate()

        measure {
            for idx in 0..<count {
                _ = self.cache["\(idx)"]
            }
        }
    }

    // MARK: - Helpers

    func populate() async {
        for idx in 0..<count {
            cache["\(idx)"] = generateRandomData()
        }
        await cache.flush()
    }
}

private func generateRandomData(count: Int = 256 * 1024) -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    assert(status == errSecSuccess)
    return Data(bytes)
}

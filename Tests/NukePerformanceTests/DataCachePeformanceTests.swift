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

    /// Stores one item at a time and waits for it to reach the disk, the way a
    /// caller that needs the data on the disk before it moves on would.
    @Test
    func writeWithFlushAfterEachItem() async {
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

    /// Reads that the staging area serves without going to the disk.
    @Test
    func readFromStaging() {
        // Small payloads: the staging lookup is the subject, not the blobs it
        // holds on to until the automatic drain gets to them.
        let data = Array(0..<count).map { _ in generateRandomData(count: 1024) }
        for index in data.indices {
            cache["\(index)"] = data[index] // No flush: the changes stay staged
        }

        measure { [cache, count] in
            for index in 0..<count {
                _ = cache["\(index)"]
            }
        }
    }

    /// The existence check that skips reading the file in.
    @Test
    func containsData() async {
        await populate()

        measure { [cache, count] in
            var hits = 0
            for index in 0..<count where cache.containsData(for: "\(index)") {
                hits += 1
            }
            return hits
        }
    }

    // MARK: - Sweep

    /// The LRU pass that runs on launch: it enumerates the directory, reads the
    /// resource values of every entry, sorts them, and removes the tail.
    @Test
    func sweep() async {
        await populate()
        cache.sizeLimit = Int.max // Measure the walk, not the removals

        await measure { [cache] in
            await cache.sweep()
        }
    }

    /// The same pass when it's over the limit and has files to delete.
    @Test
    func sweepWithEviction() async {
        let data = Array(0..<count).map { _ in generateRandomData() }

        // Each iteration re-populates what the previous one evicted. Subtract
        // the `writeWithFlush` numbers to isolate the sweep itself.
        await measure { [cache, count] in
            for index in 0..<count {
                cache["\(index)"] = data[index]
            }
            await cache.flush()
            cache.sizeLimit = cache.totalAllocatedSize / 2
            await cache.sweep()
        }
    }

    // MARK: - Concurrency

    /// Readers racing a writer for the lock that guards the staging area.
    @Test
    func concurrentReadsAndWrites() async {
        await populate()

        await measure { [cache, count] in
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<7 {
                    group.addTask {
                        for index in 0..<count {
                            _ = cache["\(index)"]
                        }
                    }
                }
                group.addTask {
                    for index in 0..<count {
                        cache["\(index)"] = Data(repeating: UInt8(index % 256), count: 1024)
                    }
                }
            }
            await cache.flush()
        }
    }

    // MARK: - Keys

    /// `filename(for:)` runs on every cache lookup, so its SHA1 is on the hot path.
    @Test
    func defaultFilenameGeneration() {
        let keys = (0..<count).map { "http://example.com/image-\($0).jpeg" }

        measure {
            var sink = 0
            for key in keys {
                sink &+= DataCache.filename(for: key)?.count ?? 0
            }
            return sink
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

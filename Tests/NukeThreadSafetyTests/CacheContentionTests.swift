// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import Testing
import Foundation
import os

// The existing thread-safety tests race the caches to catch crashes. These
// check what the racing threads see: the invariants every lock release has
// to restore, and each writer's view of its own writes.

// MARK: - ImageCache

@Suite(.timeLimit(.minutes(5)))
struct ImageCacheContentionTests {
    /// Every mutation trims under the lock, so no reader can observe the
    /// totals above the limits, and once the traffic stops, the totals add up
    /// to exactly the entries that are there – each still under its own key.
    /// With a TTL, the reads also race to remove the expired entries.
    @Test(arguments: [nil, 0.0005] as [TimeInterval?])
    func totalsStayWithinLimitsAndAddUp(ttl: TimeInterval?) {
        // Given entries of distinct costs, each always stored under its key
        let image = Test.rgbImage(width: 4, height: 4)
        let containers = (0..<64).map { ImageContainer(image: image, data: Data(count: 100 * ($0 + 1))) }
        let keys = (0..<64).map { ImageCacheKey(key: "key-\($0)") }
        let cache = ImageCache()
        cache.ttl = ttl
        cache.entryCostLimit = 1
        let costLimit = containers[0..<20].reduce(0) { $0 + cache.cost(for: $1) }
        let countLimit = 24
        cache.costLimit = costLimit
        cache.countLimit = countLimit
        let violations = OSAllocatedUnfairLock(initialState: 0)

        // When
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for _ in 0..<4000 {
                let index = Int.random(in: 0..<keys.count)
                switch Int.random(in: 0..<100) {
                case 0..<45: cache[keys[index]] = containers[index]
                case 45..<75: _ = cache[keys[index]]
                case 75..<94: cache[keys[index]] = nil
                case 94..<97: cache.trim(toCost: costLimit / 2)
                case 97..<99: cache.trim(toCount: countLimit / 2)
                default: cache.removeAll()
                }
                if cache.totalCost > costLimit || cache.totalCount > countLimit {
                    violations.withLock { $0 += 1 }
                }
            }
        }

        // Then
        #expect(violations.withLock { $0 } == 0)
        var count = 0
        var cost = 0
        for (key, container) in zip(keys, containers) {
            guard let cached = cache[key] else { continue }
            #expect(cached.data == container.data)
            count += 1
            cost += cache.cost(for: container)
        }
        #expect(cache.totalCount == count)
        #expect(cache.totalCost == cost)
    }

    /// With no limit to evict for, whatever the other threads do, a thread
    /// that owns a key reads back exactly what it last wrote to it.
    @Test func ownerReadsBackItsLastWrite() {
        // Given
        let image = Test.rgbImage(width: 4, height: 4)
        let cache = ImageCache(costLimit: .max, countLimit: .max)
        let mismatches = OSAllocatedUnfairLock(initialState: 0)

        // When
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for iteration in 0..<3000 {
                let key = ImageCacheKey(key: "\(worker)-\(iteration % 16)")
                let container = ImageContainer(image: image, data: Data("\(worker)-\(iteration)".utf8))
                cache[key] = container
                var isConsistent = cache[key]?.data == container.data
                if iteration % 3 == 0 {
                    cache[key] = nil
                    isConsistent = isConsistent && cache[key] == nil
                }
                // Contend on the keys another thread owns.
                _ = cache[ImageCacheKey(key: "\((worker + 1) % 8)-\(iteration % 16)")]
                if !isConsistent {
                    mismatches.withLock { $0 += 1 }
                }
            }
        }

        // Then
        #expect(mismatches.withLock { $0 } == 0)
    }

    /// A limit lowered while other threads keep adding entries is enforced
    /// the moment the setter returns, not on the next write.
    ///
    /// A single thread changes the limits: the setters are not safe to call
    /// from several threads at once (see the suspected bug report).
    @Test func loweredLimitsAreEnforcedDuringTraffic() {
        // Given
        let image = Test.rgbImage(width: 4, height: 4)
        let cache = ImageCache()
        cache.entryCostLimit = 1
        let container = ImageContainer(image: image, data: Data(count: 1000))
        let entryCost = cache.cost(for: container)
        let violations = OSAllocatedUnfairLock(initialState: [String]())

        // When
        DispatchQueue.concurrentPerform(iterations: 6) { worker in
            if worker == 0 {
                for iteration in 0..<500 {
                    let countLimit = 5 + iteration % 40
                    cache.countLimit = countLimit
                    if cache.totalCount > countLimit {
                        violations.withLock { $0.append("count \(cache.totalCount) > \(countLimit)") }
                    }
                    let costLimit = entryCost * (5 + (iteration * 7) % 40)
                    cache.costLimit = costLimit
                    if cache.totalCost > costLimit {
                        violations.withLock { $0.append("cost \(cache.totalCost) > \(costLimit)") }
                    }
                }
            } else {
                for iteration in 0..<5000 {
                    cache[ImageCacheKey(key: "\(worker)-\(iteration % 100)")] = container
                }
            }
        }

        // Then
        #expect(violations.withLock { $0 } == [])
        #expect(cache.countLimit == 5 + 499 % 40)
        #expect(cache.costLimit == entryCost * (5 + (499 * 7) % 40))
    }
}

// MARK: - DataCache

@Suite(.timeLimit(.minutes(5)))
struct DataCacheContentionTests {
    /// Each thread reads back its own writes and removals immediately – from
    /// the staging area or from the disk – while the automatic drains write
    /// the other threads' changes in the background; and once a `flush()`
    /// returns, everything the thread staged before it is on disk.
    @Test func ownerSeesItsChangesAndFlushPersistsThem() async throws {
        // Given
        let cache = try DataCache(path: makeUniqueDirectoryURL(), filenameGenerator: { $0 })
        cache.flushInterval = .milliseconds(1) // Keep the drains racing the writes
        defer { try? FileManager.default.removeItem(at: cache.path) }

        // When
        let models = await withTaskGroup(of: [String: Data?].self) { group in
            for worker in 0..<8 {
                group.addTask {
                    var model = [String: Data?]()
                    for iteration in 0..<300 {
                        let key = "w\(worker)-k\(iteration % 10)"
                        if iteration % 4 == 3 {
                            cache[key] = nil
                            model[key] = .some(nil)
                            #expect(cache[key] == nil)
                            #expect(!cache.containsData(for: key))
                        } else {
                            let data = Data("\(worker)-\(iteration)".utf8)
                            cache[key] = data
                            model[key] = data
                            #expect(cache[key] == data)
                        }
                        if iteration % 50 == 49 {
                            await cache.flush()
                            for (key, data) in model {
                                #expect(readFile(key, in: cache) == data, "\(key) wasn't flushed")
                            }
                        }
                    }
                    return model
                }
            }
            var models = [String: Data?]()
            for await model in group {
                models.merge(model) { $1 }
            }
            return models
        }

        // Then the disk holds exactly the last change to every key
        await cache.flush()
        for (key, data) in models {
            #expect(readFile(key, in: cache) == data)
        }
        #expect(cache.totalCount == models.values.filter { $0 != nil }.count)
    }

    /// `removeAll()` drops everything staged or written before it, but none
    /// of the writes staged after it, even when those race the drain that
    /// deletes the directory.
    @Test func removeAllKeepsTheWritesStagedAfterIt() async throws {
        // Given
        let cache = try DataCache(path: makeUniqueDirectoryURL(), filenameGenerator: { $0 })
        cache.flushInterval = .milliseconds(1)
        defer { try? FileManager.default.removeItem(at: cache.path) }
        let earlierKeys = (0..<50).map { "earlier-\($0)" }
        for key in earlierKeys {
            cache[key] = Data(key.utf8)
        }
        await cache.flush()

        // When
        cache.removeAll()
        let laterKeys = await withTaskGroup(of: [String].self) { group in
            for worker in 0..<8 {
                group.addTask {
                    var keys = [String]()
                    for index in 0..<25 {
                        let key = "later-\(worker)-\(index)"
                        cache[key] = Data(key.utf8)
                        keys.append(key)
                        #expect(cache[key] == Data(key.utf8))
                        let earlierKey = earlierKeys[(worker * 25 + index) % earlierKeys.count]
                        #expect(cache[earlierKey] == nil)
                    }
                    return keys
                }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
        await cache.flush()

        // Then
        for key in earlierKeys {
            #expect(readFile(key, in: cache) == nil)
        }
        for key in laterKeys {
            #expect(readFile(key, in: cache) == Data(key.utf8))
        }
        #expect(cache.totalCount == laterKeys.count)
    }

    /// A sweep has nothing to trim while the cache is under its size limit, so
    /// sweeps racing the writes and the drains must never delete an entry.
    @Test func sweepsUnderTheSizeLimitNeverDeleteEntries() async throws {
        // Given
        let cache = try DataCache(path: makeUniqueDirectoryURL(), filenameGenerator: { $0 })
        cache.flushInterval = .milliseconds(1)
        defer { try? FileManager.default.removeItem(at: cache.path) }

        // When
        let keys = await withTaskGroup(of: [String].self) { group in
            group.addTask {
                for _ in 0..<20 {
                    await cache.sweep()
                }
                return []
            }
            for worker in 0..<6 {
                group.addTask {
                    var keys = [String]()
                    for index in 0..<40 {
                        let key = "w\(worker)-\(index)"
                        cache[key] = Data(repeating: UInt8(index), count: 1024)
                        keys.append(key)
                        if index % 10 == 9 {
                            await cache.flush()
                        }
                    }
                    return keys
                }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
        await cache.sweep()

        // Then
        #expect(cache.totalCount == keys.count)
        for key in keys {
            #expect(readFile(key, in: cache)?.count == 1024)
        }
    }

    /// Each setting is a separate value under the cache's lock, so threads
    /// changing different settings at once – while others use the cache –
    /// never undo each other's changes.
    @Test func settingsChangedFromManyThreadsKeepTheirLastValues() async throws {
        // Given
        let cache = try DataCache(path: makeUniqueDirectoryURL(), filenameGenerator: { $0 })
        defer { try? FileManager.default.removeItem(at: cache.path) }

        // When
        DispatchQueue.concurrentPerform(iterations: 6) { worker in
            for index in 0..<300 {
                switch worker {
                case 0: cache.sizeLimit = 1_000_000 + index
                case 1: cache.sweepInterval = TimeInterval(1000 + index)
                case 2: cache.isSweepEnabled = index % 2 == 1
                case 3: cache.trimRatio = Double(index) / 1000
                case 4: cache.flushInterval = .milliseconds(index + 1)
                default:
                    cache["key-\(index % 20)"] = Data("\(index)".utf8)
                    _ = cache["key-\((index + 10) % 20)"]
                }
            }
        }

        // Then
        #expect(cache.sizeLimit == 1_000_299)
        #expect(cache.sweepInterval == 1299)
        #expect(cache.isSweepEnabled)
        #expect(cache.trimRatio == 0.299)
        #expect(cache.flushInterval == .milliseconds(300))
        await cache.flush()
        #expect(cache.totalCount == 20)
    }

    /// The pending drain keeps the cache alive, so the changes staged from many
    /// threads reach the disk even if the cache is released right away – and
    /// then nothing else keeps it alive: the scheduled sweeps hold it weakly.
    @Test func releasedCacheWritesItsStagedChangesAndGoesAway() async throws {
        // Given
        let path = makeUniqueDirectoryURL()
        defer { try? FileManager.default.removeItem(at: path) }
        let weakCache = WeakRef<DataCache>()

        // When
        do {
            let cache = try DataCache(path: path, filenameGenerator: { $0 })
            cache.flushInterval = .milliseconds(1)
            weakCache.value = cache
            DispatchQueue.concurrentPerform(iterations: 8) { worker in
                for index in 0..<10 {
                    cache["\(worker)-\(index)"] = Data("\(worker)-\(index)".utf8)
                }
            }
        }

        // Then
        await waitUntil(timeout: .seconds(60)) { weakCache.value == nil }
        for worker in 0..<8 {
            for index in 0..<10 {
                let url = path.appendingPathComponent("\(worker)-\(index)", isDirectory: false)
                let data = try? Data(contentsOf: url)
                #expect(data == Data("\(worker)-\(index)".utf8))
            }
        }
    }
}

// MARK: - ImagePipeline.Cache

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineCacheContentionTests {
    /// The synchronous `ImagePipeline.Cache` API is called from any thread.
    /// Each thread stores, reads, and removes images for its own requests in
    /// both cache layers while the others do the same.
    @Test func eachThreadSeesItsOwnChangesInBothLayers() async throws {
        // Given
        let dataCache = try DataCache(path: makeUniqueDirectoryURL())
        dataCache.flushInterval = .milliseconds(1)
        defer { try? FileManager.default.removeItem(at: dataCache.path) }
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = ImageCache()
            $0.dataCache = dataCache
        }
        let container = ImageContainer(image: Test.rgbImage(width: 8, height: 8))
        let failures = OSAllocatedUnfairLock(initialState: [String]())

        // When
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            func check(_ condition: Bool, _ message: String) {
                if !condition { failures.withLock { $0.append(message) } }
            }
            for iteration in 0..<150 {
                let request = ImageRequest(url: URL(string: "https://example.com/\(worker)/\(iteration % 15).png")!)
                pipeline.cache.storeCachedImage(container, for: request)
                check(pipeline.cache[request] != nil, "memory miss after store: \(worker)/\(iteration)")
                check(pipeline.cache.containsCachedImage(for: request, caches: .disk), "disk miss after store: \(worker)/\(iteration)")
                check(pipeline.cache.cachedData(for: request) != nil, "no data after store: \(worker)/\(iteration)")

                if iteration % 4 == 0 {
                    pipeline.cache.removeCachedImage(for: request)
                    check(pipeline.cache[request] == nil, "memory hit after remove: \(worker)/\(iteration)")
                    check(!pipeline.cache.containsCachedImage(for: request), "hit after remove: \(worker)/\(iteration)")
                    check(pipeline.cache.cachedImage(for: request) == nil, "image after remove: \(worker)/\(iteration)")
                }
            }
        }

        // Then
        #expect(failures.withLock { $0 } == [])

        // The last change to each request reaches the disk.
        await dataCache.flush()
        for worker in 0..<8 {
            for index in 0..<15 {
                let request = ImageRequest(url: URL(string: "https://example.com/\(worker)/\(index).png")!)
                // The last iteration for `index` is the largest `i < 150` with `i % 15 == index`.
                let lastIteration = 135 + index
                let isRemoved = lastIteration % 4 == 0
                #expect(pipeline.cache.containsData(for: request) == !isRemoved)
            }
        }
    }
}

// MARK: - Helpers

/// Reads the entry straight from the disk, bypassing the staging area.
private func readFile(_ key: String, in cache: DataCache) -> Data? {
    guard let url = cache.url(for: key) else { return nil }
    return try? Data(contentsOf: url)
}

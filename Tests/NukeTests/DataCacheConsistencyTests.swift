// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

private let blob = Data("123".utf8)

/// Holds up the I/O queue the first time it generates the filename for the
/// given key, which happens in the middle of a flush, until the test opens it.
private final class Gate: @unchecked Sendable {
    let entered = TestExpectation()
    private let key: String
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var isArmed = true

    init(key: String) {
        self.key = key
    }

    func pass(_ key: String) {
        guard key == self.key else { return }
        let isArmed = lock.withLock {
            defer { self.isArmed = false }
            return self.isArmed
        }
        guard isArmed else { return }
        entered.fulfill()
        semaphore.wait()
    }

    func open() {
        semaphore.signal()
    }
}

/// The reads see every change the moment it is made, however far the
/// changes have made it to the disk.
@Suite(.timeLimit(.minutes(5)))
final class DataCacheConsistencyTests {
    private let cache: DataCache

    init() throws {
        cache = try DataCache(path: makeUniqueDirectoryURL())
        cache.isSweepEnabled = false
    }

    deinit {
        cache.suspendIO()
        try? FileManager.default.removeItem(at: cache.path)
    }

    /// Runs random changes against the cache and a dictionary side by side
    /// while the automatic drain moves them to the disk in the background.
    /// A read that falls between the staging area and the disk – a change
    /// dropped from the staging area before it's written, or a removal that
    /// lets an older file through – shows up as a mismatch.
    @Test(arguments: [1, 2, 3] as [UInt64])
    func readsMatchTheLatestChangeWhileTheDrainRunsConcurrently(seed: UInt64) async throws {
        // GIVEN a drain that runs almost continuously
        cache.flushInterval = .milliseconds(1)
        var rng = SplitMix64(seed: seed)
        var model: [String: Data] = [:]
        let keys = (0..<6).map { "key\($0)" }

        // WHEN
        for step in 0..<3000 {
            let key = keys[Int(rng.next() % UInt64(keys.count))]
            switch rng.next() % 100 {
            case 0..<45:
                let data = Data("\(key)-\(step)".utf8)
                cache[key] = data
                model[key] = data
            case 45..<65:
                cache[key] = nil
                model[key] = nil
            case 65..<68:
                cache.removeAll()
                model.removeAll()
            case 68..<72:
                await cache.flush()
            default:
                break // Just read
            }

            // THEN
            for key in keys {
                let data = cache[key]
                let isContained = cache.containsData(for: key)
                guard data == model[key], isContained == (model[key] != nil) else {
                    Issue.record("Step \(step): \(key) read \(data.map { String(decoding: $0, as: UTF8.self) } ?? "nil"), contains \(isContained), expected \(model[key].map { String(decoding: $0, as: UTF8.self) } ?? "nil")")
                    return
                }
            }
        }

        // THEN the disk ends up in the same state
        await cache.flush()
        let reopened = try DataCache(path: cache.path)
        reopened.isSweepEnabled = false
        for key in keys {
            #expect(reopened[key] == model[key], "\(key)")
        }
        #expect(reopened.totalCount == model.count)
    }

    @Test func concurrentWritersEachSeeTheirOwnLatestChanges() async throws {
        // GIVEN a drain that runs almost continuously
        let cache = self.cache
        cache.flushInterval = .milliseconds(1)

        // WHEN several writers work on their own keys at the same time
        let models = await withTaskGroup(of: [String: Data].self) { group in
            for writer in 0..<4 {
                group.addTask {
                    var rng = SplitMix64(seed: UInt64(writer))
                    var model: [String: Data] = [:]
                    let keys = (0..<3).map { "writer\(writer)-key\($0)" }
                    for step in 0..<400 {
                        let key = keys[Int(rng.next() % UInt64(keys.count))]
                        if rng.next() % 3 == 0 {
                            cache[key] = nil
                            model[key] = nil
                        } else {
                            let data = Data("\(key)-\(step)".utf8)
                            cache[key] = data
                            model[key] = data
                        }
                        // THEN each of them reads back its own changes
                        for key in keys where cache[key] != model[key] {
                            Issue.record("Writer \(writer), step \(step): \(key) doesn't match")
                            return model
                        }
                    }
                    return model
                }
            }
            return await group.reduce(into: [String: Data]()) { $0.merge($1) { $1 } }
        }

        // THEN the disk ends up with all of them
        await cache.flush()
        let reopened = try DataCache(path: cache.path)
        reopened.isSweepEnabled = false
        #expect(reopened.totalCount == models.count)
        for (key, data) in models {
            #expect(reopened[key] == data, "\(key)")
        }
    }

    /// A flush in flight writes the snapshot it took before
    /// ``DataCache/removeAll()`` was staged. It must not bring those entries
    /// back once it's done: the removal stays staged until it's performed.
    @Test func removeAllStagedWhileAFlushIsInFlightWins() async throws {
        // GIVEN a flush that is in the middle of writing its snapshot
        let gate = Gate(key: "gate")
        let path = makeUniqueDirectoryURL()
        defer { try? FileManager.default.removeItem(at: path) }
        let cache = try DataCache(path: path, filenameGenerator: {
            gate.pass($0)
            return DataCache.filename(for: $0)
        })
        cache.isSweepEnabled = false
        cache.flushInterval = .seconds(60)
        cache["gate"] = blob
        for index in 0..<3 {
            cache["key\(index)"] = blob
        }
        let flush = Task { await cache.flush() }
        await gate.entered.wait()

        // WHEN
        cache.removeAll()
        cache["survivor"] = blob
        gate.open()
        await flush.value

        // THEN the entries the flush has just written stay hidden
        #expect(cache["key0"] == nil)
        #expect(cache["survivor"] == blob)

        // AND the next flush removes them from the disk
        await cache.flush()
        #expect(cache.contents.map(\.lastPathComponent) == [cache.filename(for: "survivor")])
        #expect(cache["survivor"] == blob)
        #expect(cache["gate"] == nil)
        for index in 0..<3 {
            #expect(cache["key\(index)"] == nil)
        }
    }

    /// A flush in flight writes the snapshot it took before the key was
    /// written again. It must leave the newer change staged, or the reads
    /// would find the older data it has just written.
    @Test func writeStagedWhileAFlushIsInFlightSurvivesTheFlush() async throws {
        // GIVEN a flush that is about to write the first value
        let gate = Gate(key: "key")
        let path = makeUniqueDirectoryURL()
        defer { try? FileManager.default.removeItem(at: path) }
        let cache = try DataCache(path: path, filenameGenerator: {
            gate.pass($0)
            return DataCache.filename(for: $0)
        })
        cache.isSweepEnabled = false
        cache.flushInterval = .seconds(60)
        cache["key"] = Data("A".utf8)
        let flush = Task { await cache.flush() }
        await gate.entered.wait()

        // WHEN
        cache["key"] = Data("B".utf8)
        gate.open()
        await flush.value

        // THEN the reads see the newer value
        #expect(cache["key"] == Data("B".utf8))

        // AND the next flush writes it to the disk
        await cache.flush()
        let url = try #require(cache.url(for: "key"))
        #expect(try Data(contentsOf: url) == Data("B".utf8))
    }

    @Test func flushCompletesItsWorkWhenTheAwaitingTaskIsCancelled() async {
        // GIVEN
        let cache = self.cache
        cache.flushInterval = .seconds(60)
        cache["key"] = blob

        // WHEN the flush is awaited by a task that is already cancelled
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(Task.isCancelled)
            await cache.flush()
        }
        await task.value

        // THEN the flush isn't cut short: the changes are on disk
        #expect(cache.contents.map(\.lastPathComponent) == [cache.filename(for: "key")])
    }
}

/// How long ``DataCache`` keeps itself alive.
@Suite(.timeLimit(.minutes(5)))
struct DataCacheLifetimeTests {
    @Test func idleCacheIsDeallocatedWhenReleased() throws {
        // GIVEN
        let path = makeUniqueDirectoryURL()
        defer { try? FileManager.default.removeItem(at: path) }
        var cache: DataCache? = try DataCache(path: path)
        weak var weakCache: DataCache?
        weakCache = cache

        // WHEN
        cache = nil

        // THEN the scheduled sweep doesn't keep it alive
        #expect(weakCache == nil)
    }

    @Test func stagedChangesReachTheDiskAfterTheCacheIsReleased() async throws {
        // GIVEN changes that are yet to be written
        let path = makeUniqueDirectoryURL()
        defer { try? FileManager.default.removeItem(at: path) }
        var cache: DataCache? = try DataCache(path: path)
        cache?.isSweepEnabled = false
        cache?.flushInterval = .milliseconds(100) // Long enough for the release below to come first
        cache?["key"] = blob
        weak var weakCache: DataCache?
        weakCache = cache
        let url = try #require(cache?.url(for: "key"))

        // WHEN the client lets go of the cache
        cache = nil

        // THEN the drain still writes them
        await waitUntil { FileManager.default.fileExists(atPath: url.path) }
        #expect(try Data(contentsOf: url) == blob)

        // AND the cache is gone once it's done
        await waitUntil { weakCache == nil }
    }
}

/// Looks the symbol up with `RTLD_DEFAULT`, which Swift doesn't import.
private let _isThreadSanitizerEnabled = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "__tsan_init") != nil

/// The QoS the disk I/O runs at, which is what the priority of the work
/// comes down to on the serial I/O queue.
///
/// Thread Sanitizer (enabled in the NukeTests scheme) re-submits every block
/// that goes to a queue inside a block of its own, which runs at the QoS of
/// the code that submitted it: the automatic drain comes out at the priority
/// of the test instead of `.utility`, and the rest pass whatever QoS
/// ``DataCache`` asks for.
@Suite(.timeLimit(.minutes(5)), .enabled(if: !_isThreadSanitizerEnabled, "Thread Sanitizer runs the blocks at the QoS of the code that submitted them"))
struct DataCacheQualityOfServiceTests {
    /// Records the QoS of the thread that generates the filename for the
    /// probe key: the writes are the only thing that asks for it, and they
    /// run on the I/O queue.
    private final class Probe: @unchecked Sendable {
        let key = "probe"
        let expectation = TestExpectation()
        private let lock = NSLock()
        private var _qos: qos_class_t?

        var qos: qos_class_t? { lock.withLock { _qos } }

        func record(for key: String) {
            guard key == self.key else { return }
            lock.withLock {
                if _qos == nil { _qos = qos_class_self() }
            }
            expectation.fulfill()
        }
    }

    private func makeCache(probe: Probe) throws -> DataCache {
        let cache = try DataCache(path: makeUniqueDirectoryURL(), filenameGenerator: {
            probe.record(for: $0)
            return DataCache.filename(for: $0)
        })
        cache.isSweepEnabled = false
        return cache
    }

    @Test func automaticDrainRunsAtUtility() async throws {
        // GIVEN
        let probe = Probe()
        let cache = try makeCache(probe: probe)
        defer { try? FileManager.default.removeItem(at: cache.path) }
        cache.flushInterval = .milliseconds(10)

        // WHEN
        cache[probe.key] = blob
        await probe.expectation.wait()

        // THEN it doesn't compete with the work the user is waiting for
        #expect(probe.qos == QOS_CLASS_UTILITY)

        // The probe fires before the drain writes the file: let it finish, or
        // the write re-creates the directory after the test removes it
        await cache.flush()
    }

    @Test func flushRunsAtThePriorityOfTheAwaitingTask() async throws {
        // GIVEN changes that the automatic drain won't get to first
        let probe = Probe()
        let cache = try makeCache(probe: probe)
        defer { try? FileManager.default.removeItem(at: cache.path) }
        cache.flushInterval = .seconds(60)
        cache[probe.key] = blob

        // WHEN
        await Task(priority: .userInitiated) { await cache.flush() }.value

        // THEN it isn't throttled to the QoS of the automatic drain
        let qos = try #require(probe.qos)
        #expect(qos.rawValue > QOS_CLASS_UTILITY.rawValue)
    }

    @Test func sweepRunsAtThePriorityOfTheAwaitingTask() async throws {
        // GIVEN changes that the sweep writes before it measures the size
        let probe = Probe()
        let cache = try makeCache(probe: probe)
        defer { try? FileManager.default.removeItem(at: cache.path) }
        cache.flushInterval = .seconds(60)
        cache[probe.key] = blob

        // WHEN
        await Task(priority: .userInitiated) { await cache.sweep() }.value

        // THEN
        let qos = try #require(probe.qos)
        #expect(qos.rawValue > QOS_CLASS_UTILITY.rawValue)
    }
}

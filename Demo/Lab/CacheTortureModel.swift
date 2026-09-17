// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Nuke
import Observation
import os

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Hammers the two caches Nuke ships from many threads at once, then checks
/// what they promise, and reports pass or fail with the figures.
///
/// **`DataCache`** (``DataCacheTorture``): a cache of its own in a directory
/// of its own, with a 2 MB `sizeLimit` and a `sweepInterval` of a second,
/// written, read, and emptied by a dozen tasks for a fixed time while a
/// sampler watches its size on disk.
///
/// **`ImageCache`** (``ImageCacheTorture``): `ttl`, `entryCostLimit`,
/// `costLimit` and `countLimit` under eight threads inserting at once,
/// `trim(toCost:)`, `trim(toCount:)`, and `removeAll()`, on caches of its
/// own. A second or so of work.
///
/// Neither touches a pipeline: the caches are what is under test, and they
/// are used the way a pipeline uses them, through their public API.
@MainActor @Observable
final class CacheTortureModel {
    /// How long the tasks hammer the `DataCache`, in seconds.
    var seconds = 10

    static let durations = [10, 20, 30]

    private(set) var status: Status = .idle
    /// The last `DataCache` run that went to the end.
    private(set) var dataReport: DataCacheTorture.Report?
    /// The last `ImageCache` run that went to the end.
    private(set) var imageReport: ImageCacheTorture.Report?
    /// The size on disk while a run is hammering, for the chart.
    private(set) var liveSamples: [DemoSparkline.Sample] = []
    private(set) var liveSweeps: [TimeInterval] = []

    private var task: Task<Void, Never>?

    enum Status: Equatable {
        case idle
        case hammering(elapsed: TimeInterval, total: TimeInterval)
        case checking(String)
    }

    var isRunning: Bool {
        task != nil
    }

    /// Numbers the runs, and the directories they use.
    private static var runCount = 0

    func run() {
        guard task == nil else { return }
        Self.runCount += 1
        let torture = DataCacheTorture(number: Self.runCount, seconds: seconds)
        imageReport = nil
        task = Task {
            await perform(torture)
            task = nil
            status = .idle
            liveSamples = []
            liveSweeps = []
        }
    }

    /// Stops what is running. A run that stops early leaves no report, and
    /// its directory is removed all the same.
    func stop() {
        task?.cancel()
    }

    private func perform(_ torture: DataCacheTorture) async {
        let poll = Task { [weak self] in
            while !Task.isCancelled {
                let progress = torture.progress
                self?.liveSamples = progress.samples
                self?.liveSweeps = progress.sweeps
                self?.status = progress.step.map { .checking($0) }
                    ?? .hammering(elapsed: progress.elapsed, total: TimeInterval(torture.seconds))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        let dataReport = await torture.run()
        poll.cancel()
        guard let dataReport, !Task.isCancelled else { return }
        self.dataReport = dataReport

        status = .checking("ImageCache")
        let imageReport = await ImageCacheTorture.run()
        guard !Task.isCancelled else { return }
        self.imageReport = imageReport
    }
}

// MARK: - DataCache

/// A dozen tasks writing, reading, and removing entries of a `DataCache` for a
/// fixed time, and the checks that follow.
///
/// **The cache** is new for each run, in a directory of its own under
/// `Caches/com.github.kean.NukeDemo.CacheTorture/`: two caches on one
/// directory race, a write the first one staged landing after the second
/// emptied it. Its `sizeLimit` is 2 MB and its `sweepInterval` a second. The
/// directory is removed once the cache has gone.
///
/// **The load**, from as many tasks at once:
/// - 8 writers, each the only one to touch its 40 keys: it stores an entry of
///   2–32 KB, reads it back at once, reads its keys, removes one now and then,
///   and asks `containsData`, an operation every 10 ms. Being the only writer
///   of a key, it knows what a read has to return: the bytes of its last
///   write, or nothing if a sweep took them or it removed them.
/// - 4 scanners, reading any key every 5 ms and checking that what comes
///   back is a whole entry of that key.
/// - A flusher, awaiting `flush()` every 100 ms and timing it.
/// - A sweeper, awaiting `sweep()` at 0.5, 1.5, 2.5 and 3.5 s, while the
///   cache's own sweeps haven't started: the first one comes 5 s after the
///   cache was created, whatever `sweepInterval` says.
/// - A sampler, reading `totalSize` every 100 ms, and the date the cache
///   writes into its directory after every sweep, which is the only way to
///   tell from outside that a scheduled sweep ran.
///
/// **An entry** starts with a header – a tag, its key, its version, its
/// length, and a checksum of the rest – so a read can tell a stale entry, a
/// torn one, and another key's.
final class DataCacheTorture: Sendable {
    let number: Int
    let seconds: Int
    let directory: URL

    static let sizeLimit = 2 * 1_048_576
    static let sweepInterval: TimeInterval = 1
    static let writerCount = 8
    static let keysPerWriter = 40
    static let scannerCount = 4
    /// When the sweeper calls `sweep()`, in seconds since the start: stopping
    /// a second and a half before the cache's own first sweep at 5 s, which
    /// is skipped if the last sweep was less than `sweepInterval` ago.
    static let manualSweepTimes: [TimeInterval] = [0.5, 1.5, 2.5, 3.5]
    /// How long after the cache is created it sweeps for the first time. Set
    /// by `DataCache`, not public.
    static let firstScheduledSweep: TimeInterval = 5
    static let sampleInterval: Duration = .milliseconds(100)

    static var keyCount: Int {
        writerCount * keysPerWriter
    }

    /// Where every run's directory goes. Named like every other cache of the
    /// demo, so `-demoDeterministic 1` empties it.
    static let parentDirectory = URL.cachesDirectory.appendingPathComponent("com.github.kean.NukeDemo.CacheTorture", isDirectory: true)

    private let clock = ContinuousClock()
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(number: Int, seconds: Int) {
        self.number = number
        self.seconds = seconds
        self.directory = Self.parentDirectory.appendingPathComponent("run-\(number)", isDirectory: true)
    }

    // MARK: Progress

    struct Progress: Sendable {
        var elapsed: TimeInterval = 0
        /// What is being checked once the hammering is over.
        var step: String?
        var samples: [DemoSparkline.Sample] = []
        /// The sweeps seen so far, in seconds since the start.
        var sweeps: [TimeInterval] = []
    }

    var progress: Progress {
        state.withLock { state in
            Progress(
                elapsed: state.start.map { (clock.now - $0).demoTimeInterval } ?? 0,
                step: state.step,
                samples: state.samples,
                sweeps: state.sweeps
            )
        }
    }

    private struct State {
        var start: ContinuousClock.Instant?
        var startDate = Date()
        var step: String?
        var samples: [DemoSparkline.Sample] = []
        var manualSweeps: [Report.ManualSweep] = []
        /// Every sweep seen, `sweep()` calls included.
        var sweeps: [TimeInterval] = []
        var lastSweepDate: Date?
        var flushes: [TimeInterval] = []
        var counts = Report.Counts()
        var violations: [String] = []
        var log: [Report.LogLine] = []
    }

    // MARK: Run

    /// Runs to the end and reports, or returns `nil` if it was cancelled.
    nonisolated func run() async -> Report? {
        // Whatever an earlier launch left behind. No other run is alive: the
        // model waits for one to finish before it starts the next.
        try? FileManager.default.removeItem(at: Self.parentDirectory)
        var cache: DataCache?
        do {
            cache = try DataCache(path: directory)
        } catch {
            note("couldn't create the cache: \(error)")
            return nil
        }
        // Only `cache` holds the cache once this returns, so that letting go
        // of it is enough to release it.
        let checks = await hammer(cache!)
        let cleanup = await cleanUp(&cache)
        guard let checks, !Task.isCancelled else {
            return nil
        }
        return makeReport(checks, cleanup: cleanup)
    }

    /// What the run found before it let go of the cache.
    private struct Checks {
        let finalFlush: TimeInterval
        let finalSweep: TimeInterval
        let after: Report.Size
        let removeAll: Report.RemoveAllCheck
    }

    private func hammer(_ cache: DataCache) async -> Checks? {
        cache.sizeLimit = Self.sizeLimit
        cache.sweepInterval = Self.sweepInterval
        let start = clock.now
        let deadline = start + .seconds(seconds)
        state.withLock {
            $0.start = start
            $0.startDate = Date()
        }
        note("DataCache at \(directory.lastPathComponent): sizeLimit \(demoByteCount(Self.sizeLimit)), sweepInterval \(demoSeconds(Self.sweepInterval)); \(Self.writerCount) writers × \(Self.keysPerWriter) keys, \(Self.scannerCount) scanners, for \(seconds) s")

        let ledgers = await withTaskGroup(of: Ledger?.self) { group in
            for writer in 0..<Self.writerCount {
                group.addTask { await self.write(cache, writer: writer, until: deadline) }
            }
            for scanner in 0..<Self.scannerCount {
                group.addTask { await self.scan(cache, scanner: scanner, until: deadline); return nil }
            }
            group.addTask { await self.flushRepeatedly(cache, until: deadline); return nil }
            group.addTask { await self.sweepManually(cache, start: start); return nil }
            group.addTask { await self.sample(cache, until: deadline); return nil }
            var ledgers: [Ledger] = []
            for await ledger in group {
                if let ledger {
                    ledgers.append(ledger)
                }
            }
            return ledgers
        }
        guard !Task.isCancelled else {
            return nil
        }
        let counts = state.withLock { $0.counts }
        note("\(counts.writes.formatted()) writes, \(counts.reads.formatted()) reads, \(counts.removes.formatted()) removes, \(counts.scans.formatted()) scans; \(counts.evicted.formatted()) entries found gone")

        // Settle
        setStep("the last flush and sweep")
        let finalFlush = await measure { await cache.flush() }
        let finalSweep = await measure { await cache.sweep() }
        let after = Report.Size(size: cache.totalSize, allocated: cache.totalAllocatedSize, count: cache.totalCount)
        note("flush() \(tortureDuration(finalFlush)), then sweep() \(tortureDuration(finalSweep)): \(demoByteCount(after.size)) in \(after.count) files, \(demoByteCount(after.allocated)) allocated")

        setStep("reading every key")
        for ledger in ledgers {
            for (key, expectation) in ledger.expectations {
                _ = check(cache.cachedData(for: Self.name(of: key)), key: key, expected: expectation, context: "at the end")
            }
        }

        setStep("removeAll()")
        let removeAll = await checkRemoveAll(cache)
        setStep("cleaning up")
        return Checks(finalFlush: finalFlush, finalSweep: finalSweep, after: after, removeAll: removeAll)
    }

    // MARK: Load

    /// What one writer expects of each of its keys.
    private struct Ledger: Sendable {
        var expectations: [Int: Expectation] = [:]
    }

    private enum Expectation: Sendable {
        /// Never written.
        case absent
        /// The bytes of this version, or nothing once a sweep took them.
        case stored(UInt32)
        /// Removed by the writer: nothing.
        case removed
        /// Written, then found gone: nothing, until the next write.
        case evicted
    }

    private func write(_ cache: DataCache, writer: Int, until deadline: ContinuousClock.Instant) async -> Ledger {
        var random = DemoRandomNumberGenerator(seed: UInt64(number) << 16 | UInt64(writer))
        var ledger = Ledger()
        var version: UInt32 = 0
        while clock.now < deadline, !Task.isCancelled {
            let key = writer * Self.keysPerWriter + random.next(below: Self.keysPerWriter)
            let name = Self.name(of: key)
            switch random.next(below: 100) {
            case 0..<50:
                version += 1
                cache.storeData(Self.entry(key: key, version: version, size: 2_048 + random.next(below: 30_720)), for: name)
                ledger.expectations[key] = .stored(version)
                count { $0.writes += 1 }
                if check(cache.cachedData(for: name), key: key, expected: .stored(version), context: "right after its write") == .evicted {
                    count { $0.evictedRightAfterWrite += 1 }
                    ledger.expectations[key] = .evicted
                }
            case 50..<80:
                let expected = ledger.expectations[key] ?? .absent
                if check(cache.cachedData(for: name), key: key, expected: expected, context: "on a read") == .evicted {
                    ledger.expectations[key] = .evicted
                }
            case 80..<90:
                cache.removeData(for: name)
                ledger.expectations[key] = .removed
                count { $0.removes += 1 }
                _ = check(cache.cachedData(for: name), key: key, expected: .removed, context: "right after its removal")
            default:
                let contains = cache.containsData(for: name)
                count { $0.containsCalls += 1 }
                switch ledger.expectations[key] ?? .absent {
                case .stored:
                    if !contains {
                        ledger.expectations[key] = .evicted
                        count { $0.evicted += 1 }
                    }
                case .absent, .removed, .evicted:
                    if contains {
                        violation("containsData(for:) said true for key \(key), which was \(ledger.expectations[key].map { "\($0)" } ?? "never written")")
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return ledger
    }

    private func scan(_ cache: DataCache, scanner: Int, until deadline: ContinuousClock.Instant) async {
        var random = DemoRandomNumberGenerator(seed: UInt64(number) << 16 | UInt64(100 + scanner))
        while clock.now < deadline, !Task.isCancelled {
            let key = random.next(below: Self.keyCount)
            count { $0.scans += 1 }
            if let data = cache.cachedData(for: Self.name(of: key)) {
                switch Self.parse(data) {
                case .some(let header) where header.key == key:
                    break
                case .some(let header):
                    violation("key \(key) read an entry of key \(header.key)")
                case .none:
                    violation("key \(key) read \(data.count) B that aren't a whole entry")
                }
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func flushRepeatedly(_ cache: DataCache, until deadline: ContinuousClock.Instant) async {
        while clock.now < deadline, !Task.isCancelled {
            let duration = await measure { await cache.flush() }
            state.withLock { $0.flushes.append(duration) }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func sweepManually(_ cache: DataCache, start: ContinuousClock.Instant) async {
        for time in Self.manualSweepTimes {
            try? await Task.sleep(until: start + .milliseconds(Int(time * 1000)), clock: clock)
            guard !Task.isCancelled, time < TimeInterval(seconds) else { return }
            let startedAt = (clock.now - start).demoTimeInterval
            let duration = await measure { await cache.sweep() }
            let endedAt = (clock.now - start).demoTimeInterval
            let allocated = cache.totalAllocatedSize
            let sweep = Report.ManualSweep(startedAt: startedAt, endedAt: endedAt, duration: duration, allocatedAfter: allocated)
            state.withLock { $0.manualSweeps.append(sweep) }
        }
    }

    private func sample(_ cache: DataCache, until deadline: ContinuousClock.Instant) async {
        let metadataURL = directory.appendingPathComponent(".data-cache-info", isDirectory: false)
        while clock.now < deadline, !Task.isCancelled {
            let size = cache.totalSize
            let date = Self.lastSweepDate(at: metadataURL)
            state.withLock { state in
                guard let start = state.start else { return }
                let time = (clock.now - start).demoTimeInterval
                state.samples.append(.init(time: time, value: Double(size)))
                if let date, date != state.lastSweepDate {
                    state.lastSweepDate = date
                    state.sweeps.append(date.timeIntervalSince(state.startDate))
                }
            }
            try? await Task.sleep(for: Self.sampleInterval)
        }
    }

    /// The date `DataCache` writes into its directory after a sweep: the one
    /// sign from outside that a scheduled sweep ran.
    private static func lastSweepDate(at url: URL) -> Date? {
        struct Metadata: Decodable {
            var lastSweepDate: Date?
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Metadata.self, from: data))?.lastSweepDate
    }

    // MARK: Checks

    private enum ReadOutcome {
        case matched
        case evicted
        case violation
    }

    /// Checks what a read returned against what its writer expects.
    private func check(_ data: Data?, key: Int, expected: Expectation, context: String) -> ReadOutcome {
        count { $0.reads += 1 }
        guard let data else {
            if case .stored = expected {
                count { $0.evicted += 1 }
                return .evicted
            }
            return .matched
        }
        count { $0.hits += 1 }
        guard let header = Self.parse(data) else {
            violation("key \(key) \(context): \(data.count) B that aren't a whole entry")
            return .violation
        }
        guard header.key == key else {
            violation("key \(key) \(context): an entry of key \(header.key)")
            return .violation
        }
        switch expected {
        case .stored(let version):
            guard header.version == version else {
                count { $0.stale += 1 }
                violation("key \(key) \(context): version \(header.version), not \(version)")
                return .violation
            }
            return .matched
        case .absent, .removed, .evicted:
            count { $0.resurrected += 1 }
            violation("key \(key) \(context): version \(header.version), which was \(expected)")
            return .violation
        }
    }

    private func checkRemoveAll(_ cache: DataCache) async -> Report.RemoveAllCheck {
        cache.removeAll()
        var goneAtOnce = 0
        for key in 0..<Self.keyCount where cache.cachedData(for: Self.name(of: key)) == nil && !cache.containsData(for: Self.name(of: key)) {
            goneAtOnce += 1
        }
        // Written after `removeAll()` and before it reaches the disk: the
        // drain removes everything, then writes these.
        let later = Array(0..<8)
        for key in later {
            cache.storeData(Self.entry(key: key, version: 1_000, size: 4_096), for: Self.name(of: key))
        }
        let flushDuration = await measure { await cache.flush() }
        let filesAfterFlush = cache.totalCount
        let keptLater = later.count { key in
            cache.cachedData(for: Self.name(of: key)).flatMap(Self.parse)?.version == 1_000
        }
        cache.removeAll()
        await cache.flush()
        let filesAtEnd = cache.totalCount
        note("removeAll(): \(goneAtOnce) of \(Self.keyCount) keys gone at once; \(keptLater) of \(later.count) written after it kept; flush() \(tortureDuration(flushDuration)) with \(filesAfterFlush) files; \(filesAtEnd) files after a second removeAll()")
        return .init(keyCount: Self.keyCount, goneAtOnce: goneAtOnce, laterCount: later.count, keptLater: keptLater, filesAfterFlush: filesAfterFlush, filesAtEnd: filesAtEnd)
    }

    /// Lets go of the cache, waits for it to go – a staged write keeps it
    /// until the drain has run – and removes its directory.
    private func cleanUp(_ cache: inout DataCache?) async -> Report.Cleanup {
        weak var released: DataCache?
        released = cache
        cache = nil
        let start = clock.now
        // After a Stop too: the directory goes next.
        let isReleased = await demoWait(timeout: .seconds(3), whenCancelled: .keepWaiting) { released == nil }
        let releasedAfter = isReleased ? (clock.now - start).demoTimeInterval : nil
        try? FileManager.default.removeItem(at: Self.parentDirectory)
        let isRemoved = !FileManager.default.fileExists(atPath: directory.path)
        note(releasedAfter.map { "cache released after \(tortureDuration($0))" } ?? "cache still alive after 3 s")
        note(isRemoved ? "directory removed" : "directory still there")
        return .init(releasedAfter: releasedAfter, isDirectoryRemoved: isRemoved)
    }

    // MARK: Entries

    private struct Header {
        let key: Int
        let version: UInt32
    }

    private static let tag: UInt32 = 0x4E55_4B45 // "NUKE"
    private static let headerSize = 20

    static func name(of key: Int) -> String {
        "cache-torture-\(key)"
    }

    /// A header, then `size` bytes that only this key and version make.
    private static func entry(key: Int, version: UInt32, size: Int) -> Data {
        var random = DemoRandomNumberGenerator(seed: UInt64(key) << 32 | UInt64(version))
        var payload = [UInt8](repeating: 0, count: size)
        for index in payload.indices {
            payload[index] = UInt8(truncatingIfNeeded: random.next())
        }
        var data = Data(capacity: headerSize + size)
        for field in [tag, UInt32(key), version, UInt32(size), checksum(payload)] {
            withUnsafeBytes(of: field.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: payload)
        return data
    }

    private static func parse(_ data: Data) -> Header? {
        guard data.count >= headerSize else { return nil }
        let bytes = [UInt8](data)
        func field(_ index: Int) -> UInt32 {
            let offset = index * 4
            return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        let payload = bytes[headerSize...]
        guard field(0) == tag, Int(field(3)) == payload.count, field(4) == checksum(payload) else {
            return nil
        }
        return Header(key: Int(field(1)), version: field(2))
    }

    /// FNV-1a.
    private static func checksum(_ bytes: some Sequence<UInt8>) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in bytes {
            hash = (hash ^ UInt32(byte)) &* 0x0100_0193
        }
        return hash
    }

    // MARK: Recording

    private func count(_ body: @Sendable (inout Report.Counts) -> Void) {
        state.withLock { body(&$0.counts) }
    }

    private func violation(_ text: String) {
        state.withLock { state in
            state.counts.violations += 1
            if state.violations.count < 20 {
                state.violations.append(text)
            }
        }
    }

    private func note(_ text: String) {
        state.withLock { state in
            let time = state.start.map { (clock.now - $0).demoTimeInterval } ?? 0
            state.log.append(.init(id: state.log.count, time: time, text: text))
        }
    }

    private func setStep(_ step: String) {
        state.withLock { $0.step = step }
    }

    private func measure(_ body: () async -> Void) async -> TimeInterval {
        let start = clock.now
        await body()
        return (clock.now - start).demoTimeInterval
    }
}

// MARK: - DataCache Report

extension DataCacheTorture {
    /// What a run found: the verdicts, and the figures behind them.
    struct Report: Sendable {
        let number: Int
        let seconds: Int
        /// `totalSize`, sampled every 100 ms, in bytes.
        let samples: [DemoSparkline.Sample]
        let manualSweeps: [ManualSweep]
        /// When the cache swept on its own, in seconds since the start.
        let scheduledSweeps: [TimeInterval]
        let flushes: [TimeInterval]
        let finalFlush: TimeInterval
        let finalSweep: TimeInterval
        let after: Size
        let counts: Counts
        let violations: [String]
        let removeAll: RemoveAllCheck
        let cleanup: Cleanup
        let log: [LogLine]
        var verdicts: [DemoVerdict] = []

        struct ManualSweep: Sendable {
            let startedAt: TimeInterval
            let endedAt: TimeInterval
            let duration: TimeInterval
            /// `totalAllocatedSize` read right after the call returned: what
            /// the sweep compares with the limit.
            let allocatedAfter: Int
        }

        struct Size: Sendable {
            let size: Int
            let allocated: Int
            let count: Int
        }

        struct Counts: Sendable {
            var writes = 0
            var reads = 0
            var hits = 0
            var removes = 0
            var containsCalls = 0
            var scans = 0
            /// Reads that found nothing where the writer had stored an entry:
            /// a sweep took it.
            var evicted = 0
            var evictedRightAfterWrite = 0
            var stale = 0
            var resurrected = 0
            var violations = 0
        }

        struct RemoveAllCheck: Sendable {
            let keyCount: Int
            let goneAtOnce: Int
            let laterCount: Int
            let keptLater: Int
            let filesAfterFlush: Int
            let filesAtEnd: Int

            var isPassed: Bool {
                goneAtOnce == keyCount && keptLater == laterCount && filesAfterFlush == laterCount && filesAtEnd == 0
            }
        }

        struct Cleanup: Sendable {
            let releasedAfter: TimeInterval?
            let isDirectoryRemoved: Bool
        }

        struct LogLine: Identifiable, Sendable {
            let id: Int
            let time: TimeInterval
            let text: String
        }

        /// A stretch of samples over the limit.
        struct Span {
            let start: TimeInterval
            let duration: TimeInterval
        }

        /// The stretches of samples over the limit, from the first sample over
        /// it to the first one back under it.
        var spansOverLimit: [Span] {
            var spans: [Span] = []
            var start: TimeInterval?
            for sample in samples {
                if sample.value > Double(DataCacheTorture.sizeLimit) {
                    start = start ?? sample.time
                } else if let value = start {
                    spans.append(Span(start: value, duration: sample.time - value))
                    start = nil
                }
            }
            if let start, let last = samples.last {
                spans.append(Span(start: start, duration: last.time - start + DataCacheTorture.sampleInterval.demoTimeInterval))
            }
            return spans
        }
    }

    private func makeReport(_ checks: Checks, cleanup: Report.Cleanup) -> Report {
        let state = state.withLock { $0 }
        // A date written during a `sweep()` call is that call's.
        let scheduled = state.sweeps.filter { time in
            !state.manualSweeps.contains { ($0.startedAt - 0.05)...($0.endedAt + 0.05) ~= time }
        }
        var report = Report(
            number: number,
            seconds: seconds,
            samples: state.samples,
            manualSweeps: state.manualSweeps,
            scheduledSweeps: scheduled,
            flushes: state.flushes,
            finalFlush: checks.finalFlush,
            finalSweep: checks.finalSweep,
            after: checks.after,
            counts: state.counts,
            violations: state.violations,
            removeAll: checks.removeAll,
            cleanup: cleanup,
            log: state.log
        )
        report.verdicts = Self.verdicts(for: report)
        return report
    }

    private static func verdicts(for report: Report) -> [DemoVerdict] {
        var verdicts: [DemoVerdict] = []
        let limit = Double(sizeLimit)

        // sweep()
        let manual = report.manualSweeps
        let manualOver = manual.filter { $0.allocatedAfter > sizeLimit }
        verdicts.append(DemoVerdict(
            title: "sweep() trims to the limit",
            state: manual.isEmpty ? .skipped : manualOver.isEmpty ? .passed : .failed,
            figures: "\(manual.count) calls · \(timing(manual.map(\.duration))) · after ≤ \(demoByteCount(manual.map(\.allocatedAfter).max() ?? 0))",
            detail: "Called at \(manual.map { demoSeconds($0.startedAt) }.joined(separator: ", ")), with every task still writing. A call's duration includes its wait behind a flush on the cache's one I/O queue. The figure after is the files' allocated size read right after each call, which is what a sweep compares with the limit; past the limit, it trims to 70% of it. A flush can land in between."
                + (manualOver.isEmpty ? "" : " \(manualOver.count) left the cache over the limit.")
        ))

        // Scheduled sweeps
        let scheduled = report.scheduledSweeps
        let phase = TimeInterval(report.seconds) - firstScheduledSweep
        let expected = max(0, Int(phase / sweepInterval) - 1)
        let gaps = zip(scheduled.dropFirst(), scheduled).map { $0 - $1 }
        let meanGap = gaps.isEmpty ? nil : gaps.reduce(0, +) / Double(gaps.count)
        let afterScheduled = scheduled.compactMap { time in
            report.samples.first { $0.time > time }?.value
        }
        let scheduledOver = afterScheduled.count { $0 > limit }
        let isScheduledPassed = scheduled.count >= expected && (meanGap ?? 0) <= sweepInterval * 1.5 && scheduledOver == 0
        verdicts.append(DemoVerdict(
            title: "Sweeps come every sweepInterval",
            state: isScheduledPassed ? .passed : .failed,
            figures: "\(scheduled.count) sweeps · every \(meanGap.map { String(format: "%.2fs", $0) } ?? "–") · after ≤ \(demoByteCount(Int(afterScheduled.max() ?? 0)))",
            detail: "`sweepInterval` was set to a second right after the cache was created. The first sweep the cache schedules comes 5 s after that, whatever the interval, and the rest every interval after the last one ended. A sweep is seen from outside by the date the cache writes into its directory, first at \(scheduled.first.map(demoSeconds) ?? "–"). The figure after is the first sample that followed each one. At least \(expected) were expected in \(demoSeconds(phase)).",
        ))

        // The limit holds
        let spans = report.spansOverLimit
        let longest = spans.map(\.duration).max() ?? 0
        let maxSize = report.samples.map(\.value).max() ?? 0
        let overTime = spans.reduce(0) { $0 + $1.duration }
        let total = report.samples.last?.time ?? 1
        let bound = sweepInterval * 2
        verdicts.append(DemoVerdict(
            title: "Over the limit only between sweeps",
            state: longest <= bound ? .passed : .failed,
            figures: "at most +\(demoByteCount(max(0, Int(maxSize - limit)))) · \(max(0, Int((maxSize - limit) / limit * 100)))% · longest \(demoDuration(longest)) · \(Int(overTime / total * 100))% of the time",
            detail: "`sizeLimit` is enforced when the cache sweeps, not on each write, so a cache written faster than a sweep's 30% headroom lasts goes over it between sweeps. It passes if no stretch over the limit lasted longer than two intervals, \(demoSeconds(bound)): one sweep missed would do that. \(spans.count) stretches, from the first sample over the limit to the first one back under it, 100 ms apart."
        ))

        // flush()
        let flushes = report.flushes
        let slowest = flushes.max() ?? 0
        verdicts.append(DemoVerdict(
            title: "flush() doesn't wait for the drain",
            state: flushes.isEmpty ? .skipped : slowest < 1 ? .passed : .failed,
            figures: "\(flushes.count) calls · \(timing(flushes)) · last \(tortureDuration(report.finalFlush))",
            detail: "Awaited every 100 ms while the tasks wrote. `flush()` promises to write the staged changes itself rather than wait for the automatic drain, which runs a second after a change, so no call should take a second. A call waits behind a sweep or a drain already on the queue."
        ))

        // Read your writes
        let counts = report.counts
        verdicts.append(DemoVerdict(
            title: "Reads return the last write",
            state: counts.violations == 0 ? .passed : .failed,
            figures: "\(counts.reads.formatted()) reads · \(counts.stale) stale · \(counts.resurrected) back after removal · \(counts.violations - counts.stale - counts.resurrected) torn",
            detail: "Each writer is the only one to touch its keys, so a read has to return its last write, or nothing if it removed the key or a sweep took the entry: \(counts.evicted.formatted()) reads found an entry gone, \(counts.evictedRightAfterWrite) of them right after its write. \(counts.writes.formatted()) writes, \(counts.removes.formatted()) removes, \(counts.containsCalls.formatted()) `containsData` calls, and \(counts.scans.formatted()) reads by the scanners, which check that an entry is whole and is the key's. The last read of every key came after the final flush and sweep."
                + (report.violations.isEmpty ? "" : " First: " + report.violations.prefix(3).joined(separator: "; ") + ".")
        ))

        // Under the limit when writes stop
        verdicts.append(DemoVerdict(
            title: "Under the limit once writes stop",
            state: report.after.allocated <= sizeLimit ? .passed : .failed,
            figures: "\(demoByteCount(report.after.size)) of \(demoByteCount(sizeLimit)) · \(report.after.count) files · sweep() \(tortureDuration(report.finalSweep))",
            detail: "After a last `flush()` and `sweep()`. `totalSize` adds up the files' sizes; the sweep compares their allocated size, \(demoByteCount(report.after.allocated)), with the limit."
        ))

        // removeAll()
        let removeAll = report.removeAll
        verdicts.append(DemoVerdict(
            title: "removeAll() empties it",
            state: removeAll.isPassed ? .passed : .failed,
            figures: "\(removeAll.goneAtOnce) of \(removeAll.keyCount) gone at once · \(removeAll.keptLater) of \(removeAll.laterCount) later writes kept · \(removeAll.filesAtEnd) files",
            detail: "Every key reads nothing and `containsData` says false as soon as `removeAll()` returns, before the disk has been touched. Entries written right after it survive the drain that empties the directory: \(removeAll.filesAfterFlush) files after `flush()`. A second `removeAll()` and flush leave none."
        ))

        // Cleaned up
        let cleanup = report.cleanup
        verdicts.append(DemoVerdict(
            title: "Released and removed",
            state: cleanup.releasedAfter != nil && cleanup.isDirectoryRemoved ? .passed : .failed,
            figures: (cleanup.releasedAfter.map { "released after \(tortureDuration($0))" } ?? "alive after 3 s") + " · directory " + (cleanup.isDirectoryRemoved ? "removed" : "still there"),
            detail: "The cache holds itself until a staged change has reached the disk, then goes; its scheduled sweeps don't keep it. The run's directory is removed once it has gone, so no late write can bring it back."
        ))
        return verdicts
    }

    /// "1.8ms avg · 14ms max"
    static func timing(_ values: [TimeInterval]) -> String {
        guard !values.isEmpty else { return "–" }
        let average = values.reduce(0, +) / Double(values.count)
        return "\(demoMilliseconds(average)) avg · \(demoMilliseconds(values.max() ?? 0)) max"
    }
}

// MARK: - ImageCache

/// `ImageCache` on caches of its own: its expiry, its size limits under eight
/// threads inserting at once, its trims, and `removeAll()`.
///
/// The entries are a one-pixel image with a buffer of data attached, so an
/// entry costs what the test says: `ImageCache` charges an image its bitmap
/// plus its data.
enum ImageCacheTorture {
    struct Report: Sendable {
        let verdicts: [DemoVerdict]
        let log: [String]
    }

    static let writerCount = 8
    static let insertsPerWriter = 5_000
    static let keysPerWriter = 400
    static let costLimit = 4 * 1_048_576
    static let countLimit = 200

    /// Runs every check on a thread of its own: the concurrent part blocks.
    nonisolated static func run() async -> Report {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: perform())
            }
        }
    }

    private static func perform() -> Report {
        var log: [String] = []
        let base = baseCost()
        log.append("an entry costs \(base) B plus its data")
        let verdicts = [
            checkTTL(base: base, log: &log),
            checkEntryCostLimit(base: base, log: &log),
            checkOversizedReplacement(base: base, log: &log)
        ] + checkConcurrentInserts(base: base, log: &log)
        return Report(verdicts: verdicts, log: log)
    }

    // MARK: Checks

    private static func checkTTL(base: Int, log: inout [String]) -> DemoVerdict {
        let cache = ImageCache(costLimit: 1_048_576)
        cache.ttl = 0.3
        let keys = (0..<50).map { ImageCacheKey(key: "ttl-\($0)") }
        for key in keys {
            cache[key] = makeContainer(cost: 1_024, base: base)
        }
        let hitsBefore = keys.count { cache[$0] != nil }
        Thread.sleep(forTimeInterval: 0.45)
        let heldCount = cache.totalCount
        let heldCost = cache.totalCost
        let hitsAfter = keys.count { cache[$0] != nil }
        let countAfterReads = cache.totalCount

        cache.ttl = nil
        let lasting = (0..<10).map { ImageCacheKey(key: "lasting-\($0)") }
        for key in lasting {
            cache[key] = makeContainer(cost: 1_024, base: base)
        }
        Thread.sleep(forTimeInterval: 0.45)
        let lastingHits = lasting.count { cache[$0] != nil }
        log.append("ttl 0.3 s: \(hitsBefore)/\(keys.count) hits at once, \(hitsAfter) after 0.45 s; \(heldCount) entries (\(heldCost) B) still held before those reads, \(countAfterReads) after; ttl nil: \(lastingHits)/\(lasting.count) after 0.45 s")
        let isPassed = hitsBefore == keys.count && hitsAfter == 0 && countAfterReads == 0 && lastingHits == lasting.count
        return DemoVerdict(
            title: "ttl expires entries",
            state: isPassed ? .passed : .failed,
            figures: "\(hitsBefore) of \(keys.count) before 0.3 s · \(hitsAfter) after · \(heldCount) held until read",
            detail: "With `ttl` at 0.3 s, 50 entries were there at once and gone 0.45 s later; with `ttl` back to nil, 10 more were still there after as long. An expired entry isn't removed when it expires: \(heldCount) of them, \(demoByteCount(heldCost)), still counted in `totalCount` and `totalCost`, and held their images, until a lookup found them expired, which left \(countAfterReads)."
        )
    }

    private static func checkEntryCostLimit(base: Int, log: inout [String]) -> DemoVerdict {
        let cache = ImageCache(costLimit: 1_000_000)
        let limit = Int(cache.entryCostLimit * Double(cache.costLimit))
        func isKept(cost: Int, _ name: String) -> Bool {
            let key = ImageCacheKey(key: name)
            cache[key] = makeContainer(cost: cost, base: base)
            return cache[key] != nil
        }
        let under = isKept(cost: limit - 1, "under")
        let at = isKept(cost: limit, "at")
        let over = isKept(cost: limit * 5 / 2, "over")
        cache.entryCostLimit = 0.3
        let overAfterRaise = isKept(cost: limit * 5 / 2, "over-raised")
        log.append("entryCostLimit 0.1 of \(cache.costLimit) B: \(limit - 1) B kept \(under), \(limit) B kept \(at), \(limit * 5 / 2) B kept \(over); at 0.3 kept \(overAfterRaise)")
        func kept(_ value: Bool) -> String { value ? "kept" : "refused" }
        return DemoVerdict(
            title: "entryCostLimit refuses big entries",
            state: under && !over && overAfterRaise ? .passed : .failed,
            figures: "\((limit - 1).formatted()) B \(kept(under)) · \(limit.formatted()) B \(kept(at)) · \((limit * 5 / 2).formatted()) B \(kept(over)), then \(kept(overAfterRaise))",
            detail: "A cache of 1,000,000 B with the default `entryCostLimit` of 0.1 keeps an entry under a tenth of that and refuses one of 2.5 times as much, which it keeps once the limit is raised to 0.3. An entry of exactly a tenth is \(kept(at)): the limit is compared with `<`."
        )
    }

    private static func checkOversizedReplacement(base: Int, log: inout [String]) -> DemoVerdict {
        let cache = ImageCache(costLimit: 1_000_000)
        let key = ImageCacheKey(key: "replaced")
        let small = makeContainer(cost: 10_000, base: base, tag: 1)
        let big = makeContainer(cost: 250_000, base: base, tag: 2)
        cache[key] = small
        cache[key] = big
        let found = cache[key].flatMap(tag(of:))
        let cost = cache.totalCost
        log.append("a 250,000 B image stored over a 10,000 B one: the cache returns \(found.map { $0.version == 1 ? "the old one" : "the new one" } ?? "nothing"), totalCost \(cost)")
        let keepsOld = found?.version == 1
        return DemoVerdict(
            title: "A refused image replaces the old one",
            state: keepsOld ? .expectedFailure : .passed,
            figures: found.map { $0.version == 1 ? "the old 10,000 B image still returned" : "the new image returned" } ?? "nothing returned",
            detail: keepsOld
                ? "Storing an image too big for `entryCostLimit` under a key that holds a smaller one leaves the smaller one in place, so the cache goes on returning the image the app replaced – a reload with `.reloadIgnoringCachedData`, say, whose new image is bigger. The set returns before it removes the old entry. A Nuke issue, on the list of framework asks."
                : "The cache returned no stale image for the key after refusing the new one."
        )
    }

    private struct Tag: Sendable, Equatable {
        let writer: Int
        let key: Int
        let version: Int
    }

    private static func checkConcurrentInserts(base: Int, log: inout [String]) -> [DemoVerdict] {
        let cache = ImageCache(costLimit: costLimit, countLimit: countLimit)
        struct Shared {
            var remainingWriters = ImageCacheTorture.writerCount
            var ledgers: [Int: [Int: (version: Int, cost: Int)]] = [:]
            var maxCost = 0
            var maxCount = 0
            var samples = 0
            var reads = 0
            var wrongKeys = 0
            var trims = 0
            var removeAlls = 0
        }
        let shared = OSAllocatedUnfairLock(initialState: Shared())
        let isDone: @Sendable () -> Bool = { shared.withLock { $0.remainingWriters == 0 } }
        let clock = ContinuousClock()
        let start = clock.now
        DispatchQueue.concurrentPerform(iterations: writerCount + 3) { index in
            switch index {
            case 0..<writerCount:
                var random = DemoRandomNumberGenerator(seed: UInt64(index + 1) << 20)
                var ledger: [Int: (version: Int, cost: Int)] = [:]
                for version in 0..<insertsPerWriter {
                    let slot = random.next(below: keysPerWriter)
                    let cost = 1_024 + random.next(below: 40 * 1_024)
                    cache[key(writer: index, slot: slot)] = makeContainer(cost: cost, base: base, tag: version, writer: index, key: slot)
                    ledger[slot] = (version, cost)
                }
                shared.withLock { [ledger] in
                    $0.ledgers[index] = ledger
                    $0.remainingWriters -= 1
                }
            case writerCount:
                var maxCost = 0
                var maxCount = 0
                var samples = 0
                while !isDone() {
                    maxCost = max(maxCost, cache.totalCost)
                    maxCount = max(maxCount, cache.totalCount)
                    samples += 1
                }
                shared.withLock { [maxCost, maxCount, samples] in
                    $0.maxCost = maxCost
                    $0.maxCount = maxCount
                    $0.samples = samples
                }
            case writerCount + 1:
                var random = DemoRandomNumberGenerator(seed: 7)
                var reads = 0
                var wrongKeys = 0
                while !isDone() {
                    let writer = random.next(below: writerCount)
                    let slot = random.next(below: keysPerWriter)
                    if let container = cache[key(writer: writer, slot: slot)] {
                        if let tag = tag(of: container), tag.writer != writer || tag.key != slot {
                            wrongKeys += 1
                        }
                    }
                    reads += 1
                }
                shared.withLock { [reads, wrongKeys] in
                    $0.reads = reads
                    $0.wrongKeys = wrongKeys
                }
            default:
                var random = DemoRandomNumberGenerator(seed: 11)
                var trims = 0
                var removeAlls = 0
                var iteration = 0
                while !isDone() {
                    iteration += 1
                    if iteration % 25 == 0 {
                        cache.removeAll()
                        removeAlls += 1
                    } else if iteration % 2 == 0 {
                        cache.trim(toCost: 1_048_576 + random.next(below: 3 * 1_048_576))
                        trims += 1
                    } else {
                        cache.trim(toCount: 50 + random.next(below: 150))
                        trims += 1
                    }
                    usleep(200)
                }
                shared.withLock { [trims, removeAlls] in
                    $0.trims = trims
                    $0.removeAlls = removeAlls
                }
            }
        }
        let duration = (clock.now - start).demoTimeInterval
        let figures = shared.withLock { $0 }
        let inserts = writerCount * insertsPerWriter
        log.append("\(inserts) inserts from \(writerCount) threads in \(demoDuration(duration)); \(figures.reads) reads, \(figures.trims) trims, \(figures.removeAlls) removeAll(); \(figures.samples) samples, max \(figures.maxCost) B / \(figures.maxCount)")

        var verdicts: [DemoVerdict] = []
        verdicts.append(DemoVerdict(
            title: "costLimit and countLimit hold",
            state: figures.maxCost <= costLimit && figures.maxCount <= countLimit ? .passed : .failed,
            figures: "\(inserts.formatted()) inserts on \(writerCount) threads · max \(figures.maxCost.formatted()) of \(costLimit.formatted()) B · \(figures.maxCount) of \(countLimit)",
            detail: "Entries of 1–41 KB went in from \(writerCount) threads at once, \(keysPerWriter) keys each, in \(demoDuration(duration)), while a thread read `totalCost` and `totalCount` \(figures.samples.formatted()) times, another read \(figures.reads.formatted()) entries, and a third trimmed \(figures.trims.formatted()) times to random costs and counts and called `removeAll()` \(figures.removeAlls) times. A cache trims under the lock it inserts under, so no reading should ever find it over a limit."
        ))

        // The books
        var present = 0
        var presentCost = 0
        var stale = 0
        for (writer, ledger) in figures.ledgers {
            for (slot, last) in ledger {
                guard let container = cache[key(writer: writer, slot: slot)] else { continue }
                present += 1
                presentCost += last.cost
                if tag(of: container) != Tag(writer: writer, key: slot, version: last.version) {
                    stale += 1
                }
            }
        }
        let totalCount = cache.totalCount
        let totalCost = cache.totalCost
        log.append("after: \(present) entries of \(presentCost) B read back, \(stale) stale; the cache counts \(totalCount) and \(totalCost) B")
        verdicts.append(DemoVerdict(
            title: "The counts match what it holds",
            state: stale == 0 && figures.wrongKeys == 0 && present == totalCount && presentCost == totalCost ? .passed : .failed,
            figures: "\(present) entries · \(demoByteCount(presentCost)) read back · counted \(totalCount) · \(demoByteCount(totalCost)) · \(stale) stale",
            detail: "Every thread was the only one to write its keys, so an entry still there has to be its last write: \(stale) weren't, and \(figures.wrongKeys) reads returned another key's entry. The costs of what could be read back add up to `totalCost`, and their number is `totalCount`."
        ))

        // Trims
        cache.trim(toCost: 1_048_576)
        let costAfterTrim = cache.totalCost
        cache.trim(toCount: 50)
        let countAfterTrim = cache.totalCount
        cache.costLimit = 512 * 1_024
        let costAfterLimit = cache.totalCost
        cache.countLimit = 10
        let countAfterLimit = cache.totalCount
        log.append("trim(toCost: 1 MB) → \(costAfterTrim) B; trim(toCount: 50) → \(countAfterTrim); costLimit 512 KB → \(costAfterLimit) B; countLimit 10 → \(countAfterLimit)")
        let isTrimmed = costAfterTrim <= 1_048_576 && countAfterTrim <= 50 && costAfterLimit <= 512 * 1_024 && countAfterLimit <= 10
        verdicts.append(DemoVerdict(
            title: "Trims and lowered limits",
            state: isTrimmed ? .passed : .failed,
            figures: "toCost 1 MB → \(demoByteCount(costAfterTrim)) · toCount 50 → \(countAfterTrim) · costLimit 512 KB → \(demoByteCount(costAfterLimit)) · countLimit 10 → \(countAfterLimit)",
            detail: "`trim(toCost:)` and `trim(toCount:)` evict the least recently used entries until the cache is under the figure; lowering `costLimit` or `countLimit` trims at once."
        ))

        // removeAll()
        cache.removeAll()
        let left = figures.ledgers.reduce(0) { count, entry in
            count + entry.value.keys.count { cache[key(writer: entry.key, slot: $0)] != nil }
        }
        log.append("removeAll(): \(cache.totalCount) entries, \(cache.totalCost) B, \(left) readable")
        verdicts.append(DemoVerdict(
            title: "removeAll() empties it",
            state: cache.totalCount == 0 && cache.totalCost == 0 && left == 0 ? .passed : .failed,
            figures: "\(cache.totalCount) entries · \(demoByteCount(cache.totalCost)) · \(left) readable",
            detail: "Nothing is left to count or read. It was also called during the inserts above, which the counts survived."
        ))
        return verdicts
    }

    // MARK: Entries

    private static let tagKey: ImageContainer.UserInfoKey = "com.github.kean.NukeDemo.CacheTorture.tag"

    private static func key(writer: Int, slot: Int) -> ImageCacheKey {
        ImageCacheKey(key: "writer-\(writer)-\(slot)")
    }

    private static func tag(of container: ImageContainer) -> Tag? {
        container.userInfo[tagKey] as? Tag
    }

    /// What an entry with no data costs: its one-pixel bitmap.
    private static func baseCost() -> Int {
        let cache = ImageCache(costLimit: 1_048_576)
        cache[ImageCacheKey(key: "base")] = ImageContainer(image: pixel(), data: Data())
        return cache.totalCost
    }

    /// An entry that costs `cost` bytes: a one-pixel image and the rest in
    /// data.
    private static func makeContainer(cost: Int, base: Int, tag: Int = 0, writer: Int = 0, key: Int = 0) -> ImageContainer {
        ImageContainer(
            image: pixel(),
            data: Data(count: max(0, cost - base)),
            userInfo: [tagKey: Tag(writer: writer, key: key, version: tag)]
        )
    }

    private static func pixel() -> PlatformImage {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = context?.makeImage() else {
            return PlatformImage()
        }
        #if canImport(UIKit)
        return UIImage(cgImage: image)
        #else
        return NSImage(cgImage: image, size: CGSize(width: 1, height: 1))
        #endif
    }
}

// MARK: - Helpers

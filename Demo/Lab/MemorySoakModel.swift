// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import NukeUI
import Observation

#if canImport(UIKit)
import UIKit
#endif

/// Runs the same few seconds of work over and over for up to an hour, and
/// watches whether the app's memory footprint comes back to where it was
/// after each round.
///
/// **A cycle** is about five seconds, the same every time:
/// - six animations start playing – the 200-frame GIF three times, one of
///   them smaller, the GIF, the APNG, and the animated WebP – and are
///   dropped 3.5 s later, so the frame pool makes and gives back their
///   frames every cycle;
/// - 150 loads start over 3 s (``SoakLoad``): the 12 MP JPEG in full and as a
///   thumbnail, photos resized, cropped to a circle, blurred, and as
///   thumbnails, a PNG, a GIF, and a JPEG, and a third of them are
///   cancelled within 30 ms;
/// - 1.5 s in, a cache is churned: the memory cache emptied, trimmed to a
///   quarter, or the disk cache emptied, in turn – or, 30 s into the run
///   and every two minutes after, a memory warning is posted instead;
/// - once every load has finished, both caches are emptied, and a second
///   later the footprint is read five times: the cycle's floor.
///
/// **Growth** is the slope of the floors against time, from the second
/// cycle on: the first one pays for what the app sets up once. The floor is
/// read two ways: the footprint, which is everything the system charges the
/// app for, and the heap, the bytes in use in the `malloc` zones, where every
/// object of Nuke's is. The thresholds and why are on ``SoakRecord/Measure``.
/// Each cycle also records what it left behind – tasks, players, frames,
/// cache entries, files, and pipelines – so a floor that rises can be told
/// from something still cached.
///
/// The pipeline is the run's own, through `DemoPipelineProbe`, with fixtures
/// 20 ms away, a 256 MB memory cache that takes the 12 MP image, and a disk
/// cache that stores everything, which a run empties at the start and the
/// end.
@MainActor @Observable
final class MemorySoakModel {
    /// How long a run goes on starting cycles, in minutes.
    var minutes = 1

    static let durations = [1, 5, 15, 60]

    private(set) var status: Status = .idle
    /// The run in progress, or the last one.
    private(set) var record: SoakRecord?
    /// The animations of the cycle in progress, for the screen to show.
    private(set) var players: [SoakPlayer] = []
    /// The footprint now, sampled twice a second while a run goes on.
    private(set) var footprint = DemoFootprint()

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var stopReason: SoakRecord.End?
    @ObservationIgnored private var startedAt: ContinuousClock.Instant?
    /// Kept for the model's life: every run's pipeline uses it, so no two
    /// caches are ever open on its directory.
    @ObservationIgnored private lazy var dataCache: DataCache? = try? DataCache(name: "com.github.kean.NukeDemo.MemorySoak")

    enum Status: Equatable {
        case idle
        case preparing
        case running(cycle: Int, phase: SoakPhase)
        case stopping
    }

    var isRunning: Bool {
        task != nil
    }

    /// Numbers the pipelines, so the HUD tells one run from the next.
    private static var runCount = 0

    func run() {
        guard task == nil else { return }
        Self.runCount += 1
        stopReason = nil
        let run = SoakRun(number: Self.runCount, minutes: minutes, dataCache: dataCache, model: self)
        task = Task {
            await perform(run)
            task = nil
            status = .idle
        }
    }

    /// Stops the run after it has let go of what it holds. The record keeps
    /// the cycles it finished.
    func stop(_ reason: SoakRecord.End = .stopped) {
        guard task != nil, stopReason == nil else { return }
        stopReason = reason
        task?.cancel()
    }

    private func perform(_ run: SoakRun) async {
        status = .preparing
        #if canImport(UIKit)
        let wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled }
        #endif

        await run.prepare()
        footprint = DemoFootprint()
        footprint.sample()
        startedAt = .now
        record = SoakRecord(
            number: run.number,
            label: run.label,
            minutes: run.minutes,
            startFootprint: footprint.current ?? 0,
            startLifetimePeak: footprint.lifetimePeak ?? 0
        )
        note("\(run.label): \(run.minutes) min; \(demoByteCount(footprint.current ?? 0)) to start with")

        let sampler = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        await run.perform()
        sampler.cancel()

        status = .stopping
        let releasedAfter = await run.tearDown()
        sample()
        startedAt = nil
        record?.pipelineReleasedAfter = releasedAfter
        record?.end = stopReason ?? .finished
        note(releasedAfter.map { "pipeline released after \(tortureDuration($0))" } ?? "pipeline still alive after 3 s")
        note("ended: \(record?.end?.title ?? "")")
    }

    private func sample() {
        footprint.sample()
        guard let current = footprint.current else { return }
        let time = elapsed
        record?.elapsed = time
        record?.samples.append(.init(time: time, value: Double(current)))
        let peak = max(record?.samplePeak ?? 0, current)
        record?.samplePeak = peak
        record?.lifetimePeak = footprint.lifetimePeak ?? 0
    }

    /// Reads the footprint between runs; a run samples it on its own.
    func refreshFootprint() {
        guard !isRunning else { return }
        footprint.sample()
    }

    // MARK: Run Callbacks

    fileprivate func setStatus(_ status: Status) {
        guard self.status != .stopping else { return }
        self.status = status
    }

    fileprivate func setPlayers(_ players: [SoakPlayer]) {
        self.players = players
    }

    fileprivate func append(_ cycle: SoakCycle) {
        record?.cycles.append(cycle)
    }

    fileprivate func append(_ warning: SoakWarning) {
        record?.warnings.append(warning)
    }

    fileprivate func note(_ text: String) {
        guard var record else { return }
        record.log.append(.init(id: record.log.count, time: elapsed, text: text))
        self.record = record
    }

    /// The seconds since the run started, or since the last one ended.
    fileprivate var elapsed: TimeInterval {
        startedAt.map { (ContinuousClock.now - $0).soakSeconds } ?? record?.elapsed ?? 0
    }

    /// The highest sample since `time`.
    fileprivate func peak(since time: TimeInterval) -> Int {
        Int(record?.samples.reversed().prefix { $0.time >= time }.map(\.value).max() ?? 0)
    }
}

/// What a cycle is doing.
enum SoakPhase: Equatable {
    case loading
    case draining
    case settling

    var title: String {
        switch self {
        case .loading: "loading"
        case .draining: "finishing the loads"
        case .settling: "emptied, settling"
        }
    }
}

/// An animation on screen for a cycle.
struct SoakPlayer: Identifiable {
    let id: Int
    let player: AnimatedImagePlayer
    let poster: PlatformImage
}

// MARK: - Record

/// A run: the footprint over time, and what each cycle left behind.
struct SoakRecord {
    let number: Int
    let label: String
    let minutes: Int
    /// The footprint once the fixtures were made, before the first cycle.
    let startFootprint: Int
    let startLifetimePeak: Int
    /// Seconds since the first sample.
    var elapsed: TimeInterval = 0
    /// `phys_footprint`, twice a second, in bytes.
    var samples: [DemoSparkline.Sample] = []
    var cycles: [SoakCycle] = []
    var warnings: [SoakWarning] = []
    /// The kernel's own peak footprint, at the last sample: since the app
    /// launched, making the fixtures included.
    var lifetimePeak = 0
    /// The highest footprint sampled during the run.
    var samplePeak = 0
    var pipelineReleasedAfter: TimeInterval?
    var end: End?
    var log: [LogLine] = []

    init(number: Int, label: String, minutes: Int, startFootprint: Int, startLifetimePeak: Int) {
        self.number = number
        self.label = label
        self.minutes = minutes
        self.startFootprint = startFootprint
        self.startLifetimePeak = startLifetimePeak
        self.lifetimePeak = startLifetimePeak
    }

    enum End {
        case finished
        case stopped
        /// The app left the foreground, where a run can't go on.
        case background

        var title: String {
            switch self {
            case .finished: "finished"
            case .stopped: "stopped"
            case .background: "stopped in the background"
            }
        }
    }

    struct LogLine: Identifiable {
        let id: Int
        let time: TimeInterval
        let text: String
    }

    /// The cycles the growth is measured over: all but the first, which pays
    /// for what the app sets up once.
    var countedCycles: ArraySlice<SoakCycle> {
        cycles.dropFirst(Self.warmUpCycleCount)
    }

    static let warmUpCycleCount = 1
    /// The fewest counted cycles a verdict on growth is given for.
    static let minimumCycleCount = 4

    /// What the floors are read in.
    enum Measure: CaseIterable {
        /// `phys_footprint`: all the memory the system charges the app for.
        case footprint
        /// The bytes the app's `malloc` zones have in use: every object and
        /// buffer Nuke allocates, and none of the memory the system's
        /// graphics take outside them.
        case heap

        /// The growth, in bytes a minute, that fails a run – if it also
        /// stands out from the noise by three standard errors.
        ///
        /// The footprint fails above 2 MB a minute: a cycle that kept one
        /// decoded photo, 330 KB, would add 4 MB at twelve cycles a minute,
        /// while healthy runs on the simulator rose 0.3–1.3 MB a minute over
        /// their first minutes, and 0.07 MB a minute after a quarter of an
        /// hour. The heap fails above 0.5 MB a minute: about what keeping 250
        /// bytes per load would add at 1,800 loads a minute, where healthy
        /// runs grew 0.1 MB a minute over an hour.
        var threshold: Double {
            switch self {
            case .footprint: 2 * 1_048_576
            case .heap: 1_048_576 / 2
            }
        }

        var title: String {
            switch self {
            case .footprint: "footprint"
            case .heap: "heap"
            }
        }

        func value(of cycle: SoakCycle) -> Int {
            switch self {
            case .footprint: cycle.floor
            case .heap: cycle.heap
            }
        }
    }

    /// The slope of one measure of the counted cycles against time.
    struct Growth {
        let measure: Measure
        let cycleCount: Int
        /// Bytes a minute.
        let slope: Double
        /// Of the slope, in bytes a minute; `nil` for fewer than three cycles.
        let standardError: Double?
        /// The value of the first counted cycle.
        let baseline: Int
        /// The last value minus the first.
        let change: Int
        /// The fitted line's value at the first and the last counted cycle.
        let fitted: (first: Double, last: Double)

        var isGrowing: Bool {
            slope > measure.threshold && slope > 3 * (standardError ?? .infinity)
        }
    }

    /// The footprint's growth.
    var growth: Growth? {
        growth(of: .footprint)
    }

    func growth(of measure: Measure) -> Growth? {
        let cycles = Array(countedCycles)
        guard cycles.count >= 2, let first = cycles.first, let last = cycles.last else {
            return nil
        }
        let xs = cycles.map { $0.endedAt / 60 }
        let ys = cycles.map { Double(measure.value(of: $0)) }
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        var standardError: Double?
        if cycles.count >= 3 {
            let residuals = zip(xs, ys).reduce(0) { sum, point in
                let residual = point.1 - (intercept + slope * point.0)
                return sum + residual * residual
            }
            standardError = (residuals / Double(cycles.count - 2) / sxx).squareRoot()
        }
        return Growth(
            measure: measure,
            cycleCount: cycles.count,
            slope: slope,
            standardError: standardError,
            baseline: measure.value(of: first),
            change: measure.value(of: last) - measure.value(of: first),
            fitted: (intercept + slope * xs[0], intercept + slope * xs[xs.count - 1])
        )
    }
}

/// One cycle, read once it had emptied the caches and settled.
struct SoakCycle: Identifiable {
    let number: Int
    /// Seconds since the run started, when the floor was read.
    let endedAt: TimeInterval
    /// The footprint after the caches were emptied: the median of five
    /// readings 100 ms apart, a second after.
    let floor: Int
    /// The bytes in use in the `malloc` zones, read with the floor.
    let heap: Int
    /// The highest footprint sampled during the cycle.
    let peak: Int
    let churn: SoakChurn
    /// The animations the frame pool still kept once the cycle's players
    /// and caches had let go of them, before it was asked to give them back:
    /// the pool forgets a released animation only when it next divides its
    /// budget.
    let poolKeptAnimations: Int
    let poolKeptBytes: Int
    let loadCount: Int
    let cancelCount: Int
    let failureCount: Int
    /// The decodes the probe counted: fewer when the churn left the disk
    /// cache full.
    let decodeCount: Int
    /// What was still there with the floor read.
    let left: Leftovers

    var id: Int { number }

    struct Leftovers: Equatable {
        /// `ImageTask`s of the cycle still in memory.
        var tasks = 0
        /// Players of the cycle still in memory.
        var players = 0
        /// `AnimatedImageFramePool.shared`: players drawing from it, and the
        /// animations it keeps frames of.
        var poolPlayers = 0
        var poolAnimations = 0
        var imageCacheCount = 0
        var dataCacheCount = 0
        /// Pipelines alive, the run's own included, the slot check's silent
        /// ones left out.
        var pipelines = 0

        /// Anything that should have gone with the cycle.
        var isClean: Bool {
            tasks == 0 && players == 0 && poolPlayers == 0 && poolAnimations == 0 && imageCacheCount == 0 && dataCacheCount == 0
        }
    }
}

/// What a cycle did to a cache halfway through.
enum SoakChurn: Equatable {
    case imageCacheEmptied
    case imageCacheTrimmed
    case dataCacheEmptied
    case memoryWarning

    var title: String {
        switch self {
        case .imageCacheEmptied: "memory cache emptied"
        case .imageCacheTrimmed: "memory cache trimmed"
        case .dataCacheEmptied: "disk cache emptied"
        case .memoryWarning: "memory warning"
        }
    }
}

/// A memory warning the run posted, and what it changed 200 ms later.
struct SoakWarning: Identifiable {
    let id: Int
    let time: TimeInterval
    let poolBytesBefore: Int
    let poolBytesAfter: Int
    /// The most frames any player of the cycle held afterwards.
    let bufferedFramesAfter: Int
    let imageCacheBytesBefore: Int
    let imageCacheBytesAfter: Int
}

// MARK: - Verdicts

extension SoakRecord {
    var verdicts: [DemoVerdict] {
        var verdicts: [DemoVerdict] = []
        let megabyte = 1_048_576.0

        // Growth
        for measure in Measure.allCases {
            let title = measure == .footprint ? "Footprint flat after the first cycle" : "Heap flat after the first cycle"
            guard let growth = growth(of: measure), growth.cycleCount >= Self.minimumCycleCount else {
                verdicts.append(DemoVerdict(
                    title: title,
                    state: .skipped,
                    figures: "\(countedCycles.count) of \(Self.minimumCycleCount) cycles after the first",
                    detail: "The slope needs \(Self.minimumCycleCount) cycles after the first, about 25 s."
                ))
                continue
            }
            let error = growth.standardError.map { String(format: " ± %.2f", $0 / megabyte) } ?? ""
            let what = measure == .footprint
                ? "the footprint once the caches were emptied"
                : "the bytes the `malloc` zones had in use at the same moment, where every object and buffer of Nuke's is"
            let why = measure == .footprint
                ? "A cycle that kept one decoded photo would add twice that. On the simulator, healthy runs grew 0.3–1.3 MB a minute over their first minutes, mostly outside the heap, and 0.07 MB a minute after a quarter of an hour."
                : "Keeping 250 bytes per load – a task, a closure – would add about that; healthy runs of an hour grew 0.1 MB a minute. A heap that stays flat while the footprint grows is memory the system took, not objects the app kept."
            verdicts.append(DemoVerdict(
                title: title,
                state: growth.isGrowing ? .failed : .passed,
                figures: String(format: "%+.2f", growth.slope / megabyte) + error + " MB/min · \(growth.cycleCount) cycles · " + String(format: "%+.1f MB", Double(growth.change) / megabyte) + " since cycle 2",
                detail: "The slope of each cycle's \(measure.title) – \(what) – against time, from cycle 2 on, with its standard error. It fails above " + String(format: "%g", measure.threshold / megabyte) + " MB a minute, if that is also three standard errors above zero, so a short run's noise doesn't. \(why) Cycle 2 read \(demoByteCount(growth.baseline))."
            ))
        }

        // Leftovers
        let dirty = cycles.filter { !$0.left.isClean }
        let kept = cycles.filter { $0.poolKeptAnimations > 0 }
        let worst = cycles.reduce(into: SoakCycle.Leftovers()) { worst, cycle in
            worst.tasks = max(worst.tasks, cycle.left.tasks)
            worst.players = max(worst.players, cycle.left.players)
            worst.poolAnimations = max(worst.poolAnimations, cycle.left.poolAnimations)
            worst.imageCacheCount = max(worst.imageCacheCount, cycle.left.imageCacheCount)
            worst.dataCacheCount = max(worst.dataCacheCount, cycle.left.dataCacheCount)
        }
        verdicts.append(DemoVerdict(
            title: "Nothing left after a cycle",
            state: cycles.isEmpty ? .skipped : dirty.isEmpty ? .passed : .failed,
            figures: "\(cycles.count - dirty.count) of \(cycles.count) clean · at most \(worst.tasks) tasks · \(worst.players) players · \(worst.poolAnimations) animations · \(worst.imageCacheCount) images · \(worst.dataCacheCount) files",
            detail: "Once a cycle's loads have finished and its caches are emptied, none of its `ImageTask`s or players may still be in memory, the frame pool may hold no animation, and both caches must be empty. Tasks are given a second to go, and players two. Before the count, the pool is asked to give back what nobody plays, with `removeIdleAnimations()`: "
                + (kept.isEmpty ? "it kept nothing of any cycle." : "it still kept the frames of animations the cache had let go of after \(kept.count) cycles, at most \(kept.map(\.poolKeptAnimations).max() ?? 0) animations and \(demoByteCount(kept.map(\.poolKeptBytes).max() ?? 0)). It sweeps them only when it next divides its budget – on the framework asks.")
                + (dirty.isEmpty ? "" : " Left behind in cycles " + dirty.prefix(8).map { "\($0.number)" }.joined(separator: ", ") + ".")
        ))

        // Pipelines
        let counts = Set(cycles.map(\.left.pipelines))
        let isReleased = end == nil || pipelineReleasedAfter != nil
        verdicts.append(DemoVerdict(
            title: "Pipelines don't pile up",
            state: cycles.isEmpty ? .skipped : counts.count == 1 && isReleased ? .passed : .failed,
            figures: (counts.count == 1 ? "\(counts.first ?? 0) alive after every cycle" : "\(counts.min() ?? 0)–\(counts.max() ?? 0) alive")
                + (end == nil ? "" : pipelineReleasedAfter.map { " · released after \(tortureDuration($0))" } ?? " · alive after 3 s"),
            detail: "The pipelines `DemoPipelineProbe` sees alive – the shared one, the run's own, and any another screen left – counted after every cycle; the slot check's silent ones, which never go, are left out. The run's pipeline has to go once the run lets go of it."
        ))

        // Memory warnings
        if warnings.isEmpty {
            verdicts.append(DemoVerdict(
                title: "Memory warnings answered",
                state: .skipped,
                figures: "none posted yet",
                detail: "The first is posted 30 s into a run."
            ))
        } else {
            let answered = warnings.filter { $0.poolBytesAfter <= $0.poolBytesBefore && $0.bufferedFramesAfter <= 2 }
            let first = warnings[0]
            verdicts.append(DemoVerdict(
                title: "Memory warnings answered",
                state: answered.count == warnings.count ? .passed : .failed,
                figures: "\(warnings.count) posted · pool \(demoByteCount(first.poolBytesBefore)) → \(demoByteCount(first.poolBytesAfter)) · ≤ \(warnings.map(\.bufferedFramesAfter).max() ?? 0) frames · image cache \(demoByteCount(first.imageCacheBytesBefore)) → \(demoByteCount(first.imageCacheBytesAfter))",
                detail: "`UIApplication.didReceiveMemoryWarningNotification`, posted 30 s into the run and every two minutes after, while the animations play. The frame pool answers it: every player holds two frames, for a minute. `ImageCache` doesn't: it empties itself on the system's memory-pressure event, which a posted notification doesn't raise, so its figure stays. Read 200 ms after posting; the figures are the first warning's."
            ))
        }
        return verdicts
    }
}

// MARK: - Run

/// One run: its pipeline, the script of a cycle, and the loads in flight.
@MainActor
private final class SoakRun {
    let number: Int
    let minutes: Int
    let label: String

    private weak var model: MemorySoakModel?
    private let dataCache: DataCache?
    private let imageCache: ImageCache
    private var pipeline: ImagePipeline?
    private let clock = ContinuousClock()

    /// The loads of the cycle not yet finished, by number.
    private var inFlight: [Int: ImageTask] = [:]
    private var tasks: [WeakTask] = []
    private var players: [WeakPlayer] = []
    private var loadNumber = 0
    private var counts = Counts()
    private var nextWarning: TimeInterval = SoakRun.firstWarning

    static let loadsPerCycle = 150
    static let loadRate = 50.0
    static let churnTime: TimeInterval = 1.5
    static let animationTime: TimeInterval = 3.5
    static let firstWarning: TimeInterval = 30
    static let warningInterval: TimeInterval = 120

    private static let photoCount = DemoFixture.photos.count

    private struct Counts {
        var loads = 0
        var cancels = 0
        var failures = 0
    }

    private struct WeakTask {
        weak var task: ImageTask?
    }

    private struct WeakPlayer {
        weak var player: AnimatedImagePlayer?
    }

    init(number: Int, minutes: Int, dataCache: DataCache?, model: MemorySoakModel) {
        self.number = number
        self.minutes = minutes
        self.label = "Memory Soak · \(number)"
        self.dataCache = dataCache
        self.model = model
        self.imageCache = ImageCache(costLimit: 256 * 1_048_576)
        // A quarter of the limit, so that the 12 MP image, 46 MB decoded, is
        // cached rather than refused.
        imageCache.entryCostLimit = 0.25
    }

    /// Makes every fixture a cycle loads, before the footprint is first read,
    /// and empties the disk cache an earlier run may have left.
    func prepare() async {
        let fixtures: [DemoFixture] = [.largeJPEG, .jpeg, .png, .gif, .longGIF, .apng, .animatedWebP] + DemoFixture.photos
        for fixture in fixtures {
            _ = try? await DemoFixtureStore.shared.entry(for: fixture)
        }
        if let dataCache {
            dataCache.removeAll()
            await dataCache.flush()
        }
        var configuration = ImagePipeline.Configuration(dataLoader: DemoFixtureLoader(pace: .init(latency: .milliseconds(20))))
        configuration.imageCache = imageCache
        configuration.dataCache = dataCache
        configuration.dataCachePolicy = .storeAll
        pipeline = DemoPipelineProbe.makePipeline(label, configuration: configuration)
    }

    /// Cycles until the time is up or the run is cancelled.
    func perform() async {
        var cycle = 0
        while let model, model.elapsed < TimeInterval(minutes * 60), !Task.isCancelled {
            cycle += 1
            guard let result = await perform(cycle: cycle) else { return }
            model.append(result)
        }
    }

    /// Cancels what is left, empties the caches, and lets go of the pipeline;
    /// returns how long it took to go.
    func tearDown() async -> TimeInterval? {
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
        model?.setPlayers([])
        pipeline?.cache.removeAll()
        await dataCache?.flush()
        weak var released: ImagePipeline?
        released = pipeline
        pipeline = nil
        let start = clock.now
        // After a Stop too, which is when it runs most.
        let isReleased = await demoWait(timeout: .seconds(3), every: .milliseconds(10), whenCancelled: .keepWaiting) { released == nil }
        return isReleased ? (clock.now - start).soakSeconds : nil
    }

    // MARK: Cycle

    private func perform(cycle: Int) async -> SoakCycle? {
        guard let pipeline, let model else { return nil }
        let start = clock.now
        let startedAt = model.elapsed
        counts = Counts()
        tasks.removeAll()
        players.removeAll()
        let decodesBefore = DemoPipelineProbe.diagnostics(for: pipeline)?.decoding.count ?? 0
        model.setStatus(.running(cycle: cycle, phase: .loading))

        let animations = Task { await self.startAnimations(cycle: cycle) }
        // A cycle that ends early takes its animations with it: they are
        // still loading, and would start playing after the tear-down.
        defer { animations.cancel() }

        var churn = SoakChurn.imageCacheEmptied
        var hasChurned = false
        var started = 0
        while started < Self.loadsPerCycle {
            guard !Task.isCancelled else { return nil }
            let elapsed = (clock.now - start).soakSeconds
            let due = min(Self.loadsPerCycle, Int(elapsed * Self.loadRate) + 1)
            while started < due {
                startLoad()
                started += 1
            }
            if !hasChurned, elapsed >= Self.churnTime {
                hasChurned = true
                churn = await self.churn(cycle: cycle)
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        try? await Task.sleep(until: start + .milliseconds(Int(Self.animationTime * 1000)), clock: clock)
        await animations.value
        model.setPlayers([])
        guard !Task.isCancelled else { return nil }

        // Every load finishes, or 10 s pass.
        model.setStatus(.running(cycle: cycle, phase: .draining))
        await demoWait(timeout: .seconds(10)) { inFlight.isEmpty }
        guard !Task.isCancelled else { return nil }

        // Empty the caches, and let what goes with them go.
        model.setStatus(.running(cycle: cycle, phase: .settling))
        pipeline.cache.removeAll()
        await dataCache?.flush()
        await waitUntil(timeout: .seconds(1)) { $0.tasks.allSatisfy { $0.task == nil } }
        await waitUntil(timeout: .seconds(2)) { $0.players.allSatisfy { $0.player == nil } }
        // The pool keeps the frames of an animation nobody plays until it next
        // divides its budget, even once nothing else holds the animation. It
        // is asked to let go, as it does in the background, and what it kept
        // is recorded apart.
        let pool = AnimatedImageFramePool.shared
        let kept = (animations: pool.animationCount, bytes: pool.totalCost)
        pool.removeIdleAnimations()
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return nil }

        var floors: [Int] = []
        var heaps: [Int] = []
        for _ in 0..<5 {
            if let figures = DemoFootprint.read() {
                floors.append(figures.footprint)
            }
            heaps.append(Self.heapInUse())
            try? await Task.sleep(for: .milliseconds(100))
        }
        let floor = floors.sorted()[floors.count / 2]
        let heap = heaps.sorted()[heaps.count / 2]
        let dataCacheCount = await dataCacheCount()
        let left = SoakCycle.Leftovers(
            tasks: tasks.count { $0.task != nil },
            players: players.count { $0.player != nil },
            poolPlayers: pool.playerCount,
            poolAnimations: pool.animationCount,
            imageCacheCount: imageCache.totalCount,
            dataCacheCount: dataCacheCount,
            pipelines: DemoPipelineProbe.pipelines.count { !$0.label.hasPrefix(SlotCheck.silentLabel) }
        )
        let decodes = (DemoPipelineProbe.diagnostics(for: pipeline)?.decoding.count ?? 0) - decodesBefore
        let endedAt = model.elapsed
        return SoakCycle(
            number: cycle,
            endedAt: endedAt,
            floor: floor,
            heap: heap,
            peak: model.peak(since: startedAt),
            churn: churn,
            poolKeptAnimations: kept.animations,
            poolKeptBytes: kept.bytes,
            loadCount: counts.loads,
            cancelCount: counts.cancels,
            failureCount: counts.failures,
            decodeCount: decodes,
            left: left
        )
    }

    /// The bytes in use in every `malloc` zone of the process.
    static func heapInUse() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return statistics.size_in_use
    }

    private func waitUntil(timeout: Duration, _ condition: (SoakRun) -> Bool) async {
        await demoWait(timeout: timeout) { condition(self) }
    }

    private func dataCacheCount() async -> Int {
        guard let dataCache else { return 0 }
        return await Task.detached(priority: .utility) { dataCache.totalCount }.value
    }

    // MARK: Churn

    private func churn(cycle: Int) async -> SoakChurn {
        guard let model else { return .imageCacheEmptied }
        if model.elapsed >= nextWarning {
            nextWarning += Self.warningInterval
            await postMemoryWarning(at: model.elapsed)
            return .memoryWarning
        }
        switch cycle % 3 {
        case 1:
            imageCache.removeAll()
            return .imageCacheEmptied
        case 2:
            imageCache.trim(toCost: imageCache.costLimit / 4)
            return .imageCacheTrimmed
        default:
            dataCache?.removeAll()
            return .dataCacheEmptied
        }
    }

    private func postMemoryWarning(at time: TimeInterval) async {
        let pool = AnimatedImageFramePool.shared
        let poolBefore = pool.totalCost
        let imageCacheBefore = imageCache.totalCost
        #if canImport(UIKit)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: UIApplication.shared)
        #else
        pool.reduceMemoryUsage()
        #endif
        try? await Task.sleep(for: .milliseconds(200))
        let frames = players.compactMap { $0.player?.diagnostics.bufferedFrameCount }.max() ?? 0
        let warning = SoakWarning(
            id: (model?.record?.warnings.count ?? 0) + 1,
            time: time,
            poolBytesBefore: poolBefore,
            poolBytesAfter: pool.totalCost,
            bufferedFramesAfter: frames,
            imageCacheBytesBefore: imageCacheBefore,
            imageCacheBytesAfter: imageCache.totalCost
        )
        model?.append(warning)
        model?.note("memory warning: pool \(demoByteCount(poolBefore)) → \(demoByteCount(warning.poolBytesAfter)), players hold ≤ \(frames) frames; image cache \(demoByteCount(imageCacheBefore)) → \(demoByteCount(warning.imageCacheBytesAfter))")
    }

    // MARK: Animations

    /// The animations of a cycle: loaded through the run's pipeline, so they
    /// go when the caches are emptied and the players let go of them.
    private func startAnimations(cycle: Int) async {
        guard let pipeline else { return }
        let plan: [(DemoFixture, CGFloat?)] = [
            (.longGIF, nil), (.longGIF, nil), (.longGIF, 120), (.gif, nil), (.apng, nil), (.animatedWebP, nil)
        ]
        var containers: [DemoFixture: ImageContainer] = [:]
        for fixture in Set(plan.map(\.0)) {
            containers[fixture] = try? await pipeline.imageTask(with: fixture.url).response.container
        }
        guard !Task.isCancelled else { return }
        var soakPlayers: [SoakPlayer] = []
        for (index, item) in plan.enumerated() {
            guard let container = containers[item.0], let source = container.animation else { continue }
            var options = AnimatedImagePlayer.Options()
            options.maxPixelSize = item.1
            options.scale = container.image.scale
            let player = AnimatedImagePlayer(source: source, options: options)
            player.play()
            players.append(WeakPlayer(player: player))
            soakPlayers.append(SoakPlayer(id: cycle * 10 + index, player: player, poster: container.image))
        }
        model?.setPlayers(soakPlayers)
    }

    // MARK: Loads

    private func startLoad() {
        guard let pipeline else { return }
        let number = loadNumber
        loadNumber += 1
        let task = pipeline.imageTask(with: SoakLoad.request(number, photoCount: Self.photoCount))
        tasks.append(WeakTask(task: task))
        inFlight[number] = task
        counts.loads += 1
        Task { [weak self] in
            let result: Result<ImageResponse, ImagePipeline.Error>
            do throws(ImagePipeline.Error) {
                result = .success(try await task.response)
            } catch {
                result = .failure(error)
            }
            self?.didFinish(number, result)
        }
        if number % 3 == 2 {
            // Spread over 30 ms, the same way on every run: most land before
            // the fixture's 20 ms are up, some while it decodes.
            let delay = (number * 7) % 30
            if delay == 0 {
                task.cancel()
            } else {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(delay))
                    self?.inFlight[number]?.cancel()
                }
            }
        }
    }

    private func didFinish(_ number: Int, _ result: Result<ImageResponse, ImagePipeline.Error>) {
        guard inFlight.removeValue(forKey: number) != nil else { return }
        switch result {
        case .success:
            break
        case .failure(.cancelled):
            counts.cancels += 1
        case .failure:
            counts.failures += 1
        }
    }
}

/// The requests of a cycle, in turn.
enum SoakLoad: CaseIterable {
    case largeJPEG
    case largeThumbnail
    case resized
    case circle
    case blurred
    case thumbnail
    case photo
    case png
    case gif
    case jpeg

    /// The order they come in, twelve to a round.
    private static let order: [SoakLoad] = [.largeJPEG, .largeThumbnail, .resized, .circle, .blurred, .thumbnail, .photo, .resized, .png, .gif, .thumbnail, .jpeg]

    var title: String {
        switch self {
        case .largeJPEG: "the 12 MP JPEG, decoded in full"
        case .largeThumbnail: "the 12 MP JPEG as a 1024 px thumbnail"
        case .resized: "a photo resized to 150 px"
        case .circle: "a photo resized and cropped to a circle"
        case .blurred: "a photo resized and blurred"
        case .thumbnail: "a photo as a 160 px thumbnail"
        case .photo: "a photo as it is"
        case .png: "the PNG"
        case .gif: "the GIF, with its data"
        case .jpeg: "the 1440×960 JPEG resized to 400 px"
        }
    }

    static func request(_ number: Int, photoCount: Int) -> ImageRequest {
        let photo = DemoFixture.photo(number % photoCount).url
        // Three versions of the 12 MP image a cycle, so each is decoded more
        // than once and cached.
        let variant = URLQueryItem(name: "v", value: String((number / order.count) % 3))
        switch order[number % order.count] {
        case .largeJPEG:
            return ImageRequest(url: url(DemoFixture.largeJPEG.url, variant))
        case .largeThumbnail:
            var request = ImageRequest(url: url(DemoFixture.largeJPEG.url, variant))
            request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 1024)
            return request
        case .resized:
            return ImageRequest(url: photo, processors: [.resize(size: CGSize(width: 150, height: 150), unit: .pixels, crop: true)])
        case .circle:
            return ImageRequest(url: photo, processors: [.resize(size: CGSize(width: 150, height: 150), unit: .pixels, crop: true), .circle()])
        case .blurred:
            return ImageRequest(url: photo, processors: [.resize(size: CGSize(width: 120, height: 120), unit: .pixels, crop: true), .gaussianBlur(radius: 4)])
        case .thumbnail:
            var request = ImageRequest(url: photo)
            request.thumbnail = ImageRequest.ThumbnailOptions(size: CGSize(width: 160, height: 160), unit: .pixels)
            return request
        case .photo:
            return ImageRequest(url: photo)
        case .png:
            return ImageRequest(url: DemoFixture.png.url)
        case .gif:
            return ImageRequest(url: DemoFixture.gif.url)
        case .jpeg:
            return ImageRequest(url: DemoFixture.jpeg.url, processors: [.resize(width: 400, unit: .pixels)])
        }
    }

    private static func url(_ url: URL, _ item: URLQueryItem) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [item]
        return components?.url ?? url
    }
}

extension Duration {
    fileprivate var soakSeconds: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

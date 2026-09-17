// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import Observation
import QuartzCore

/// Drives a workload through a pipeline of its own and samples, ten times a
/// second, where each of its tasks is, what the five task queues are doing,
/// and how long the main thread stalled.
///
/// **A run** gets a new pipeline, "Concurrency Inspector · N", so the counts
/// of one never mix with the next. It loads fixtures, 60 ms of latency and
/// then six chunks 40 ms apart, has no memory cache, and has a disk cache
/// that keeps nothing (``DiscardingDataCache``), so that the pipeline encodes
/// the processed images and thumbnails its policy would store. Every request
/// has a URL of its own, `?run=R&n=N`, so only the two tasks of a pair share
/// work. The pipeline keeps running what the last run left – the encodes, if
/// the queue was suspended – until the next run replaces it.
///
/// **What it sees**: the record (``InspectorRecorder``) is written by the
/// pipeline's delegate (``InspectorDelegate``), by the decoder, encoder, and
/// processor that delegate hands out, and by the probe's reports of every
/// call to the loader. The figures of the queues' work running come from the
/// probe; the work waiting is the screen's own tracking of its requests,
/// because `TaskQueue` keeps that count to itself.
///
/// **The queue controls** are the screen's settings, applied to every
/// pipeline it builds and to the current one at once: a limit and a
/// suspension per queue. Pause suspends all five on top of them and stops
/// the workload starting tasks; Resume puts both back.
///
/// **The watchdog** is a ``DemoDisplayMonitor`` whose late frames are listed
/// one by one, and a ``DemoMainThreadPinger``. A stall seen by both is one
/// row.
@MainActor @Observable
final class ConcurrencyInspectorModel {
    var workload = InspectorWorkload.burst

    private(set) var status = Status.idle
    private(set) var isPaused = false
    private(set) var run: RunSummary?
    /// The run's tasks at the last sample.
    private(set) var sample = InspectorSample()
    /// The unfinished tasks, over the last ``seriesDuration`` seconds.
    private(set) var series: [TimedValue] = []
    private(set) var queues: [QueueStatus] = []
    private(set) var pipelineLabel = ""
    /// The queues of every pipeline alive.
    private(set) var pipelines: [PipelineQueues] = []
    private(set) var display = DemoDisplayMonitor.Figures()
    private(set) var ping = DemoMainThreadPinger.Figures()
    /// Newest last.
    private(set) var stalls: [Stall] = []
    /// How long reading the record takes.
    private(set) var samplingCost = InspectorWait()

    /// The limit each queue is given, by the screen.
    private(set) var limits: [InspectorQueue: Int]
    /// The queues the screen keeps suspended, Pause aside.
    private(set) var suspended: Set<InspectorQueue> = []

    static let seriesDuration: TimeInterval = 30
    static let stallThreshold: TimeInterval = 0.016
    static let limitChoices = [1, 2, 3, 4, 6, 8, 12]

    /// The current pipeline, the record its delegate writes, and the
    /// processor its requests use. Made the first time the screen asks
    /// rather than in `init`, which SwiftUI runs each time it makes the view,
    /// keeping only the first model.
    @ObservationIgnored private var rig: Rig?
    /// The tasks not yet finished, by index.
    @ObservationIgnored private var handles: [Int: ImageTask] = [:]
    @ObservationIgnored private var generator: Task<Void, Never>?
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private let monitor = DemoDisplayMonitor()
    @ObservationIgnored private let pinger = DemoMainThreadPinger(threshold: ConcurrencyInspectorModel.stallThreshold)
    @ObservationIgnored private var stallCount = 0
    @ObservationIgnored private var runCount = 0
    /// The run's clock, which stands still while paused.
    @ObservationIgnored private var clock = RunClock()

    /// Numbers the pipelines across the screen's visits, so the HUD tells
    /// them apart.
    private static var pipelineCount = 0

    /// 60 ms before the first byte, then six chunks 40 ms apart: 0.3 s a
    /// download, whatever its size, so six slots take about 20 a second.
    nonisolated static let pace = DemoFixtureLoader.Pace(latency: .milliseconds(60), chunkCount: 6, interval: .milliseconds(40))

    enum Status: Equatable {
        case idle
        case preparing
        /// Starting tasks, or, for a burst, waiting for them.
        case running
        /// Stopped or cancelled, and waiting for the tasks started to
        /// finish.
        case stopping
        case finished
    }

    struct RunSummary: Equatable {
        let number: Int
        let workload: InspectorWorkload
        let startedAt: CFTimeInterval
        var endedAt: CFTimeInterval?
    }

    struct TimedValue: Equatable {
        let time: CFTimeInterval
        let value: Double
    }

    /// A queue of the current pipeline.
    struct QueueStatus: Identifiable, Equatable {
        let queue: InspectorQueue
        var limit: Int
        var isSuspended: Bool
        /// The probe's count of the work running, or `nil` where it can't
        /// see it.
        var inFlight: Int?
        var figures: InspectorQueueFigures

        var id: InspectorQueue { queue }

        /// The work running: the probe's count, or the screen's where the
        /// probe has none.
        var running: Int {
            inFlight ?? figures.running
        }
    }

    struct PipelineQueues: Identifiable, Equatable {
        let id: ObjectIdentifier
        let label: String
        let queues: [DemoPipelineDiagnostics.Queue]

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.label == rhs.label && zip(lhs.queues, rhs.queues).allSatisfy {
                $0.inFlightCount == $1.inFlightCount && $0.limit == $1.limit && $0.isSuspended == $1.isSuspended
            }
        }
    }

    /// A stall of the main thread, as the display link, the pinger, or both
    /// saw it.
    struct Stall: Identifiable, Equatable {
        let id: Int
        var hitch: DemoDisplayMonitor.Hitch?
        var ping: DemoMainThreadPinger.Stall?
        /// When it started, in the time base of `CACurrentMediaTime()`.
        var startedAt: CFTimeInterval
        let date: Date

        /// How long the main thread was held: the display link's figure if
        /// it saw the stall, which is its measure of what a user saw.
        var duration: TimeInterval {
            hitch?.stall ?? ping?.duration ?? 0
        }

        /// The span the stall covered, for matching the two sources.
        var span: ClosedRange<CFTimeInterval> {
            let start = min(hitch.map { $0.timestamp - $0.duration } ?? .infinity, ping?.startedAt ?? .infinity)
            let end = max(hitch?.timestamp ?? -.infinity, ping?.endedAt ?? -.infinity)
            return start...max(start, end)
        }
    }

    init() {
        let defaults = ImagePipeline.Configuration()
        limits = Dictionary(uniqueKeysWithValues: InspectorQueue.allCases.map {
            ($0, $0.queue(in: defaults).maxConcurrentTaskCount)
        })
        monitor.onHitch = { [weak self] hitch in
            self?.didHitch(hitch)
        }
    }

    var isRunning: Bool {
        generator != nil
    }

    // MARK: Pipeline

    private struct Rig {
        let pipeline: ImagePipeline
        let recorder: InspectorRecorder
        let processor: InspectedProcessor
    }

    private var pipeline: ImagePipeline { currentRig.pipeline }
    private var recorder: InspectorRecorder { currentRig.recorder }
    private var processor: InspectedProcessor { currentRig.processor }

    private var currentRig: Rig {
        rig ?? makeRig()
    }

    /// Makes a pipeline with the screen's settings the current one.
    @discardableResult
    private func makeRig() -> Rig {
        let (pipeline, recorder, processor) = Self.makePipeline(limits: limits, suspended: suspended, isPaused: isPaused)
        let rig = Rig(pipeline: pipeline, recorder: recorder, processor: processor)
        self.rig = rig
        pipelineLabel = DemoPipelineProbe.probe(for: pipeline)?.label ?? ""
        return rig
    }

    private static func makePipeline(limits: [InspectorQueue: Int], suspended: Set<InspectorQueue>, isPaused: Bool) -> (ImagePipeline, InspectorRecorder, InspectedProcessor) {
        pipelineCount += 1
        let recorder = InspectorRecorder()
        var configuration = ImagePipeline.Configuration(dataLoader: DemoFixtureLoader(pace: pace))
        configuration.imageCache = nil
        configuration.dataCache = DiscardingDataCache()
        configuration.dataCachePolicy = .automatic
        // Hundreds of records a run, and the probe times decoders only for a
        // pipeline that doesn't record them.
        configuration.isDiagnosticsEnabled = false
        for queue in InspectorQueue.allCases {
            let taskQueue = queue.queue(in: configuration)
            taskQueue.maxConcurrentTaskCount = limits[queue] ?? taskQueue.maxConcurrentTaskCount
            taskQueue.isSuspended = isPaused || suspended.contains(queue)
        }
        let pipeline = DemoPipelineProbe.makePipeline(
            "Concurrency Inspector · \(pipelineCount)",
            configuration: configuration,
            delegate: InspectorDelegate(recorder: recorder),
            onLoad: { [recorder] event in
                recorder.record(event)
            }
        )
        return (pipeline, recorder, InspectedProcessor(recorder: recorder))
    }

    /// A new pipeline for a run, unless the current one hasn't run anything.
    /// The one replaced gets its queues back, so nothing it holds waits on a
    /// queue that nobody can resume.
    private func preparePipeline() {
        guard recorder.hasTasks else { return }
        resumeQueues(of: pipeline)
        makeRig()
        sample = recorder.sample()
    }

    private func resumeQueues(of pipeline: ImagePipeline) {
        for queue in InspectorQueue.allCases {
            queue.queue(in: pipeline.configuration).isSuspended = false
        }
    }

    private func applySettings() {
        for queue in InspectorQueue.allCases {
            let taskQueue = queue.queue(in: pipeline.configuration)
            if let limit = limits[queue], taskQueue.maxConcurrentTaskCount != limit {
                taskQueue.maxConcurrentTaskCount = limit
            }
            taskQueue.isSuspended = isPaused || suspended.contains(queue)
        }
        sampleQueues()
    }

    func setLimit(_ limit: Int, for queue: InspectorQueue) {
        limits[queue] = limit
        applySettings()
    }

    func toggleSuspended(_ queue: InspectorQueue) {
        if suspended.contains(queue) {
            suspended.remove(queue)
        } else {
            suspended.insert(queue)
        }
        applySettings()
    }

    // MARK: Runs

    func start() {
        guard generator == nil else { return }
        preparePipeline()
        runCount += 1
        let number = runCount
        let workload = workload
        run = RunSummary(number: number, workload: workload, startedAt: CACurrentMediaTime())
        status = .preparing
        generator = Task {
            await perform(workload, run: number)
            generator = nil
            if var summary = self.run {
                summary.endedAt = CACurrentMediaTime()
                self.run = summary
            }
            status = .finished
            // Nothing left to pause once a run is over.
            if isPaused {
                resume()
            }
        }
    }

    /// Stops starting tasks. The ones started finish.
    func stop() {
        guard status == .running else { return }
        status = .stopping
    }

    /// Stops starting tasks and suspends every queue: what is running
    /// finishes, and everything else waits where it is.
    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        clock.pause()
        applySettings()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        clock.resume()
        applySettings()
    }

    /// Cancels every task and ends the run.
    func cancelAll() {
        guard isRunning else { return }
        if status == .running || status == .preparing {
            status = .stopping
        }
        let tasks = handles.values
        handles.removeAll()
        for task in tasks {
            task.cancel()
        }
        if isPaused {
            resume()
        }
    }

    /// The screen is going: the run is cancelled, and the queues resumed.
    func leave() {
        cancelAll()
        generator?.cancel()
        if let rig {
            resumeQueues(of: rig.pipeline)
        }
    }

    private func perform(_ workload: InspectorWorkload, run number: Int) async {
        for fixture in [DemoFixture.largeJPEG] + DemoFixture.photos {
            _ = try? await DemoFixtureStore.shared.entry(for: fixture)
        }
        guard status == .preparing, !Task.isCancelled else { return }
        status = .running
        clock = RunClock()
        if isPaused {
            clock.pause()
        }
        switch workload {
        case .burst: startBurst(run: number)
        case .trickle: await trickle(run: number)
        case .scroll: await scroll(run: number)
        }
        while recorder.unsettledCount > 0, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// 240 requests at once, a sixth of them `.high` and a sixth `.low`.
    private func startBurst(run number: Int) {
        for count in 0..<InspectorWorkload.burstCount {
            let priority: ImageRequest.Priority = switch count % 6 {
            case 0: .high
            case 3: .low
            default: .normal
            }
            startRequest(run: number, kind: InspectorWorkload.kind(count), priority: priority)
        }
    }

    /// A request every 1/8 s, until stopped.
    private func trickle(run number: Int) async {
        var count = 0
        while status == .running, !Task.isCancelled {
            if !isPaused {
                let due = Int(clock.elapsed * InspectorWorkload.trickleRate) + 1
                while count < due {
                    startRequest(run: number, kind: InspectorWorkload.kind(count), priority: .normal)
                    count += 1
                }
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Rows of four thumbnails going past, until stopped. A row's requests
    /// start `.low`, half a second before it comes into view, as a
    /// prefetcher's would; go `.normal` once it is in view; and are
    /// cancelled a second later, when it leaves.
    private func scroll(run number: Int) async {
        struct Row {
            let appearedAt: TimeInterval
            var keys: [InspectorTaskKey]
            var isVisible = false
        }
        var rows: [Row] = []
        var rowCount = 0
        let tiles = InspectorWorkload.scrollTiles
        while status == .running, !Task.isCancelled {
            if !isPaused {
                let now = clock.elapsed
                let due = Int(now * InspectorWorkload.scrollRowsPerSecond) + 1
                while rowCount < due {
                    var keys: [InspectorTaskKey] = []
                    for tile in tiles {
                        keys += startRequest(run: number, kind: tile, priority: .low)
                    }
                    rows.append(Row(appearedAt: Double(rowCount) / InspectorWorkload.scrollRowsPerSecond, keys: keys))
                    rowCount += 1
                }
                for index in rows.indices {
                    let age = now - rows[index].appearedAt
                    if !rows[index].isVisible, age >= InspectorWorkload.scrollLead {
                        rows[index].isVisible = true
                        for key in rows[index].keys {
                            setPriority(.normal, for: key)
                        }
                    }
                }
                rows.removeAll { row in
                    guard now - row.appearedAt >= InspectorWorkload.scrollLead + InspectorWorkload.scrollVisible else {
                        return false
                    }
                    for key in row.keys {
                        cancel(key)
                    }
                    return true
                }
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Starts the tasks of one request: one, or two for a pair.
    @discardableResult
    private func startRequest(run number: Int, kind: InspectorKind, priority: ImageRequest.Priority) -> [InspectorTaskKey] {
        let unit = recorder.registerRequest(kind: kind)
        let request = makeRequest(kind: kind, unit: unit, run: number, priority: priority)
        var keys = [startTask(request, unit: unit, kind: kind, isPartner: false)]
        if kind == .pair {
            keys.append(startTask(request, unit: unit, kind: kind, isPartner: true))
        }
        return keys
    }

    private func startTask(_ request: ImageRequest, unit: Int, kind: InspectorKind, isPartner: Bool) -> InspectorTaskKey {
        let key = recorder.registerTask(unit: unit, isPartner: isPartner, kind: kind, priority: request.priority)
        var request = request
        request.userInfo[InspectorTaskKey.userInfoKey] = key
        handles[key.index] = pipeline.imageTask(with: request)
        return key
    }

    private func makeRequest(kind: InspectorKind, unit: Int, run number: Int, priority: ImageRequest.Priority) -> ImageRequest {
        let fixture = kind.fixture(unit: unit)
        var components = URLComponents(url: fixture.url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "run", value: String(number)), URLQueryItem(name: "n", value: String(unit))]
        let url = components?.url ?? fixture.url
        var request = ImageRequest(url: url, processors: kind.isProcessed ? [processor] : [], priority: priority)
        switch kind {
        case .thumbnail:
            request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 64)
        case .largeThumbnail:
            request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 480)
        default:
            break
        }
        return request
    }

    private func setPriority(_ priority: ImageRequest.Priority, for key: InspectorTaskKey) {
        guard let task = handles[key.index] else { return }
        task.priority = priority
        recorder.priorityChanged(key, to: priority)
    }

    private func cancel(_ key: InspectorTaskKey) {
        handles.removeValue(forKey: key.index)?.cancel()
    }

    // MARK: Watching

    /// Samples ten times a second, and watches the main thread, while the
    /// screen is on display.
    func startWatching() {
        applySettings()
        monitor.start()
        pinger.start()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sampleNow()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopWatching() {
        samplingTask?.cancel()
        samplingTask = nil
        monitor.stop()
        pinger.stop()
    }

    /// Starts the watchdog's figures and list over.
    func clearStalls() {
        monitor.reset()
        pinger.reset()
        stalls = []
        display = monitor.figures
        ping = pinger.figures
    }

    /// Blocks the main thread, for the watchdog to catch.
    func stallMainThread(for milliseconds: Int) {
        Thread.sleep(forTimeInterval: Double(milliseconds) / 1000)
    }

    private func sampleNow() {
        let sample = recorder.sample()
        self.sample = sample
        for index in recorder.takeFinished() {
            handles[index] = nil
        }
        samplingCost.record(sample.duration)

        let now = sample.time
        series.append(TimedValue(time: now, value: Double(sample.activeCount)))
        if let first = series.firstIndex(where: { $0.time >= now - Self.seriesDuration }), first > 0 {
            series.removeFirst(first)
        }

        sampleQueues()
        let pipelines = DemoPipelineProbe.liveProbes.map { probe in
            let diagnostics = probe.diagnostics
            return PipelineQueues(id: ObjectIdentifier(probe), label: probe.label, queues: InspectorQueue.allCases.map { $0.figures(in: diagnostics) })
        }
        if pipelines != self.pipelines {
            self.pipelines = pipelines
        }

        display = monitor.figures
        ping = pinger.figures
        for stall in pinger.takeStalls() {
            add(ping: stall)
        }
    }

    private func sampleQueues() {
        let diagnostics = DemoPipelineProbe.diagnostics(for: pipeline)
        let queues = InspectorQueue.allCases.map { queue in
            let taskQueue = queue.queue(in: pipeline.configuration)
            return QueueStatus(
                queue: queue,
                limit: taskQueue.maxConcurrentTaskCount,
                isSuspended: taskQueue.isSuspended,
                inFlight: diagnostics.flatMap { queue.figures(in: $0).inFlightCount },
                figures: sample.queues[queue] ?? InspectorQueueFigures()
            )
        }
        if queues != self.queues {
            self.queues = queues
        }
    }

    // MARK: Stalls

    private func didHitch(_ hitch: DemoDisplayMonitor.Hitch) {
        guard hitch.stall > Self.stallThreshold else { return }
        let start = hitch.timestamp - hitch.duration
        if let index = stalls.lastIndex(where: { $0.hitch == nil && Self.overlaps($0.span, start...hitch.timestamp) }) {
            stalls[index].hitch = hitch
            stalls[index].startedAt = min(stalls[index].startedAt, start)
        } else {
            append(Stall(id: nextStallID(), hitch: hitch, startedAt: start, date: Self.date(of: start)))
        }
    }

    private func add(ping: DemoMainThreadPinger.Stall) {
        if let index = stalls.lastIndex(where: { $0.ping == nil && Self.overlaps($0.span, ping.startedAt...ping.endedAt) }) {
            stalls[index].ping = ping
        } else {
            append(Stall(id: nextStallID(), ping: ping, startedAt: ping.startedAt, date: Self.date(of: ping.startedAt)))
        }
    }

    private func append(_ stall: Stall) {
        stalls.append(stall)
        if stalls.count > 50 {
            stalls.removeFirst(stalls.count - 50)
        }
    }

    private func nextStallID() -> Int {
        stallCount += 1
        return stallCount
    }

    /// Whether two spans overlap, give or take a refresh: a display link
    /// learns of a stall at the next frame, the pinger as soon as it ends.
    private static func overlaps(_ lhs: ClosedRange<CFTimeInterval>, _ rhs: ClosedRange<CFTimeInterval>) -> Bool {
        let slack = 0.02
        return lhs.lowerBound <= rhs.upperBound + slack && rhs.lowerBound <= lhs.upperBound + slack
    }

    private static func date(of time: CFTimeInterval) -> Date {
        Date(timeIntervalSinceNow: time - CACurrentMediaTime())
    }
}

/// The workloads a run can drive.
enum InspectorWorkload: String, CaseIterable, Identifiable, Sendable {
    case burst
    case trickle
    case scroll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .burst: "Burst"
        case .trickle: "Trickle"
        case .scroll: "Scroll"
        }
    }

    var summary: String {
        switch self {
        case .burst: "\(Self.burstCount) requests at once, every kind, a sixth of them high priority and a sixth low. Ends when the last task does."
        case .trickle: "A request every \(Int(1000 / Self.trickleRate)) ms, every kind, well within what the queues take. Runs until stopped."
        case .scroll: "\(Int(Self.scrollRowsPerSecond)) rows a second of \(Self.scrollTiles.count) thumbnails going by: each starts low half a second before its row shows, goes normal while it shows, and is cancelled when it leaves. More than the queues take. Runs until stopped."
        }
    }

    /// The kinds of request, in the order a run cycles through them.
    static let pattern: [InspectorKind] = [
        .photo, .blurred, .thumbnail, .photo, .pair, .blurred,
        .photo, .thumbnail, .largeThumbnail, .blurred, .photo, .large
    ]
    static let burstCount = 240

    /// The kind of a run's `n`th request.
    static func kind(_ n: Int) -> InspectorKind {
        pattern[n % pattern.count]
    }
    /// Requests a second.
    static let trickleRate = 8.0
    static let scrollRowsPerSecond = 8.0
    static let scrollTiles: [InspectorKind] = [.thumbnail, .blurred, .photo, .thumbnail]
    /// How long before a row shows its requests start.
    static let scrollLead: TimeInterval = 0.5
    /// How long a row shows.
    static let scrollVisible: TimeInterval = 1
}

/// Seconds since a run started, not counting the time it was paused.
private struct RunClock {
    private var start = CACurrentMediaTime()
    private var pausedAt: CFTimeInterval?
    private var pausedTotal: TimeInterval = 0

    var elapsed: TimeInterval {
        (pausedAt ?? CACurrentMediaTime()) - start - pausedTotal
    }

    mutating func pause() {
        pausedAt = pausedAt ?? CACurrentMediaTime()
    }

    mutating func resume() {
        guard let pausedAt else { return }
        pausedTotal += CACurrentMediaTime() - pausedAt
        self.pausedAt = nil
    }
}

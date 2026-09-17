// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import Observation
import os

/// Starts image tasks at a fixed rate, cancels them at every point of their
/// lives, and checks what the pipeline promises about cancellation once they
/// are done. Then, on request, checks what a loader that follows the
/// documented cancel contract does to the data loading queue.
///
/// **A run** builds a pipeline of its own, so nothing a run leaves behind
/// reaches the next one, and releases it at the end. The pipeline has no
/// caches, decodes progressive previews as soon as a scan arrives, and loads
/// fixtures: 40 ms of latency, then four chunks 15 ms apart. The tasks cycle
/// through five kinds of request (``TortureKind``), five points to cancel at
/// (``TortureCancelPoint``), and three ways of listening (``TortureAPI``), so
/// every combination comes up every 75 requests, in the same order on every
/// run. A task is cancelled on the main thread, the way an app cancels one.
///
/// Once every task has finished, and a moment more for anything late, the run
/// checks that:
/// - no closure was called after `cancel()`, and no event followed
///   `.finished`, on the delegate or on a stream;
/// - every task finished exactly once, and every way of listening heard the
///   same outcome;
/// - no `ImageTask` is left in memory;
/// - the probe's counts of the downloads, decodes and decompressions in
///   flight, and the run's own count of the processing, are back to zero;
/// - every task that wasn't cancelled before it finished got its image;
/// - a new request on the same pipeline completes;
/// - the pipeline goes away once the run lets go of it;
/// - the tasks really started at the rate asked for.
///
/// **The slot check** (``SlotCheck``) takes every data loading slot of a
/// pipeline with slow downloads, cancels them midway, and asks for one more
/// image, once with a loader that calls `completion` after a cancel and once
/// with one that doesn't, as the documentation of `DataLoading` asks. The
/// second never gets a slot: the pipeline frees one only on `completion`.
@MainActor @Observable
final class CancellationTortureModel {
    /// The tasks a run starts per second.
    var rate = 200
    /// How long a run goes on starting tasks, in seconds.
    var duration = 5

    static let rates = [50, 100, 200, 400]
    static let durations = [2, 5, 10]

    private(set) var status: Status = .idle
    /// The last run that went to the end.
    private(set) var report: TortureReport?
    /// The last slot check that went to the end.
    private(set) var slotReport: SlotReport?

    private var task: Task<Void, Never>?

    /// What the model is doing.
    enum Status: Equatable {
        case idle
        case preparing
        case starting(started: Int, total: Int)
        case draining(left: Int)
        case checking(String)
        case slotCheck(String)
    }

    var isRunning: Bool {
        task != nil
    }

    func runTorture() {
        start { await $0.torture() }
    }

    func runSlotCheck() {
        start { await $0.slotCheck() }
    }

    /// A run, then the slot check: what `-demoAutorun 1` starts.
    func runAll() {
        start { model in
            await model.torture()
            guard !Task.isCancelled else { return }
            await model.slotCheck()
        }
    }

    /// Stops what is running. A run that stops early leaves no report.
    func stop() {
        task?.cancel()
    }

    private func start(_ body: @escaping @MainActor (CancellationTortureModel) async -> Void) {
        guard task == nil else { return }
        task = Task {
            await body(self)
            task = nil
            status = .idle
        }
    }

    // MARK: Runs

    /// Numbers the pipelines, so the HUD tells one run from the next.
    private static var runCount = 0

    private func torture() async {
        Self.runCount += 1
        let run = TortureRun(number: Self.runCount, rate: rate, seconds: duration)
        let report = await run.perform { [weak self] status in
            self?.status = status
        }
        if let report {
            self.report = report
        }
    }

    private func slotCheck() async {
        if let conditions = DemoNetworkConditions.shared.badge {
            slotReport = SlotReport(results: [], skippedFor: conditions)
            return
        }
        Self.runCount += 1
        var results: [SlotCheck.Result] = []
        for completes in [true, false] {
            status = .slotCheck(completes ? "a loader that completes" : "a loader that stays silent")
            guard let result = await SlotCheck.run(completesCancelledLoads: completes, number: Self.runCount), !Task.isCancelled else {
                return
            }
            results.append(result)
        }
        slotReport = SlotReport(results: results, skippedFor: nil)
    }
}

// MARK: - Report

/// What a run found: the verdicts, and the figures behind them.
struct TortureReport: Sendable {
    let number: Int
    let label: String
    let rate: Int
    let seconds: Int
    /// The network conditions that were on, if any.
    let conditions: String?
    let requestCount: Int
    let taskCount: Int
    /// From the first task created to the last.
    let startSpan: TimeInterval
    let cancelCount: Int
    /// The cancels made before the last task was created.
    let cancelsWhileStarting: Int
    /// From the last task created to the last one finished.
    let drainDuration: TimeInterval
    let unsettledCount: Int
    let aliveTaskCount: Int
    /// How long the tasks took to go once every one had finished.
    let tasksGoneAfter: TimeInterval?
    let queues: Queues
    let fresh: Fresh
    /// `nil` if the pipeline was still there after 3 seconds.
    let pipelineReleasedAfter: TimeInterval?
    let loadCount: Int
    let peakProcessingCount: Int
    let figures: Figures
    let violations: [String]
    let violationCount: Int
    let log: [LogLine]
    var verdicts: [DemoVerdict] = []

    struct Queues: Sendable {
        var loading: Int?
        var loadingLimit = 0
        var stuck = 0
        var decoding: Int?
        var decompressing: Int?
        var encoding: Int?
        var processing = 0
        var activeTasks = 0
        var inFlightBytes: Int64 = 0
        /// How long they took to settle, or `nil` if they didn't within 2 s.
        var settledAfter: TimeInterval?

        var isIdle: Bool {
            [loading, decoding, decompressing, encoding].allSatisfy { ($0 ?? 0) == 0 }
                && stuck == 0 && processing == 0 && activeTasks == 0 && inFlightBytes == 0
        }
    }

    enum Fresh: Sendable {
        case completed(TimeInterval)
        case failed(String, TimeInterval)
        case timedOut(TimeInterval)
    }

    struct LogLine: Identifiable, Sendable {
        let id: Int
        let time: TimeInterval
        let text: String
    }

    /// The counts the tables show.
    struct Figures: Sendable {
        var landings: [TortureLanding: Int] = [:]
        var kinds: [TortureKind: Row] = [:]
        var apis: [TortureAPI: Row] = [:]
        var notCancelledCount = 0

        struct Row: Sendable {
            var tasks = 0
            var cancelled = 0
            var images = 0
            var failed = 0
            var callbacks = 0
            var previews = 0

            fileprivate mutating func add(_ log: TortureTaskLog) {
                tasks += 1
                callbacks += log.eventCount + log.clientEventCount + log.closureCallCount
                previews += log.previewCount
                switch log.result {
                case .image?: images += 1
                case .cancelled?: cancelled += 1
                case .failed?: failed += 1
                case nil: break
                }
            }
        }
    }
}

/// The last slot check: one result per loader, or why it didn't run.
struct SlotReport: Sendable {
    let results: [SlotCheck.Result]
    /// The network conditions that kept it from running.
    let skippedFor: String?

    /// Pipelines of the silent loader still alive: their slots keep them.
    @MainActor
    var leakedPipelineCount: Int {
        DemoPipelineProbe.pipelines.count { $0.label.hasPrefix(SlotCheck.silentLabel) }
    }
}

// MARK: - Run

/// One run: its pipeline, the tasks it started, and what it heard.
@MainActor
private final class TortureRun {
    let number: Int
    let rate: Int
    let seconds: Int
    let label: String

    private let recorder = TortureRecorder(latency: TortureRun.pace.latency)
    private let clock = ContinuousClock()
    private var pipeline: ImagePipeline?
    private weak var releasedPipeline: ImagePipeline?
    private let processor: ImageProcessors.Anonymous
    /// The tasks not yet cancelled, or not yet finished for a partner.
    private var handles: [TortureTaskKey: Handle] = [:]
    /// Every task started, to find out whether any is left.
    private var tasks: [WeakTask] = []
    private var lines: [TortureReport.LogLine] = []
    private var startedAt: ContinuousClock.Instant
    private var requestCount = 0
    private var createdCount = 0
    private var firstCreatedAt: ContinuousClock.Instant?
    private var lastCreatedAt: ContinuousClock.Instant?
    private var cancelCount = 0
    private var cancelsWhileStarting = 0
    private var isStarting = false

    /// 40 ms before the first byte, then four chunks 15 ms apart: about a
    /// tenth of a second for a photo, a fifth for the progressive JPEG,
    /// which comes a scan per chunk.
    nonisolated static let pace = DemoFixtureLoader.Pace(latency: .milliseconds(40), chunkCount: 4, interval: .milliseconds(15))

    private nonisolated static let photoCount = DemoFixture.photos.count

    private struct Handle {
        let task: ImageTask
        /// The Swift task awaiting the response, which is what the app
        /// cancels for ``TortureAPI/response``.
        let awaiting: Task<Void, Never>?
    }

    private struct WeakTask {
        weak var task: ImageTask?
    }

    init(number: Int, rate: Int, seconds: Int) {
        self.number = number
        self.rate = rate
        self.seconds = seconds
        self.label = "Cancellation Torture · \(number)"
        self.startedAt = ContinuousClock.now
        self.processor = recorder.makeProcessor()
    }

    /// Runs to the end and reports, or returns `nil` if it was cancelled.
    func perform(status: (CancellationTortureModel.Status) -> Void) async -> TortureReport? {
        status(.preparing)
        let conditions = DemoNetworkConditions.shared.badge
        // Made before the clock starts, so the first run isn't slower.
        for fixture in [DemoFixture.progressiveJPEG] + DemoFixture.photos {
            _ = try? await DemoFixtureStore.shared.entry(for: fixture)
        }
        makePipeline()
        startedAt = clock.now
        note("\(label): \(rate) tasks/s for \(seconds) s, fixtures at 40 ms + 4 × 15 ms, no caches")
        if let conditions {
            note("network conditions on: \(conditions)")
        }

        let triggers = recorder.triggers
        let consumer = Task { [weak self] in
            for await trigger in triggers {
                self?.handle(trigger)
            }
        }
        defer { consumer.cancel() }

        // Start
        let total = rate * seconds
        var lastStatus = clock.now
        isStarting = true
        while createdCount < total {
            guard !Task.isCancelled else { return abandon() }
            let due = min(total, Int(Double(rate) * (clock.now - startedAt).seconds) + 1)
            while createdCount < due {
                startRequest(requestCount)
                requestCount += 1
            }
            if clock.now - lastStatus > .milliseconds(100) {
                status(.starting(started: createdCount, total: total))
                lastStatus = clock.now
            }
            try? await Task.sleep(for: .milliseconds(4))
        }
        isStarting = false
        let startSpan = (firstCreatedAt.flatMap { first in lastCreatedAt.map { $0 - first } } ?? .zero).seconds
        note("started \(createdCount.formatted()) tasks for \(requestCount.formatted()) requests in \(demoSeconds(startSpan)); \(cancelCount.formatted()) cancelled so far")

        // Drain
        let drainStart = clock.now
        var unsettled = recorder.unsettledCount
        while unsettled > 0 {
            guard !Task.isCancelled else { return abandon() }
            if clock.now - drainStart > .seconds(30) {
                note("gave up after 30 s with \(unsettled) tasks unfinished")
                break
            }
            status(.draining(left: unsettled))
            try? await Task.sleep(for: .milliseconds(50))
            unsettled = recorder.unsettledCount
        }
        let drainDuration = (clock.now - drainStart).seconds
        note("every task finished \(demoSeconds(drainDuration)) after the last one started; \(recorder.snapshot.loadCount.formatted()) loads")

        // Anything late has half a second to show up.
        status(.checking("listening for late callbacks"))
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return abandon() }
        recorder.finishTriggers()
        if !handles.isEmpty {
            note("\(handles.count) tasks were never cancelled or finished: \(handles.keys.prefix(5).map(\.description).joined(separator: ", "))")
            handles.removeAll()
        }

        status(.checking("waiting for the tasks to go"))
        let tasksGoneAfter = await waitUntil(timeout: .seconds(2)) { $0.aliveTaskCount == 0 }
        let aliveTaskCount = aliveTaskCount
        note(tasksGoneAfter.map { "every ImageTask gone after \(tortureDuration($0))" } ?? "\(aliveTaskCount.formatted()) ImageTasks still alive after 2 s")

        status(.checking("waiting for the queues"))
        var queues = currentQueues()
        let queuesSettledAfter = await waitUntil(timeout: .seconds(2)) {
            queues = $0.currentQueues()
            return queues.isIdle
        }
        queues.settledAfter = queuesSettledAfter
        note(queuesSettledAfter.map { "queues idle after \(tortureDuration($0))" } ?? "queues still busy after 2 s")

        status(.checking("a new request"))
        let fresh = await startFreshRequest()
        switch fresh {
        case .completed(let time): note("a new request completed in \(tortureDuration(time))")
        case let .failed(error, time): note("a new request failed in \(tortureDuration(time)): \(error)")
        case .timedOut(let time): note("a new request didn't finish in \(tortureDuration(time))")
        }

        status(.checking("releasing the pipeline"))
        releasedPipeline = pipeline
        pipeline = nil
        let pipelineReleasedAfter = await waitUntil(timeout: .seconds(3)) { $0.releasedPipeline == nil }
        note(pipelineReleasedAfter.map { "pipeline released after \(tortureDuration($0))" } ?? "pipeline still alive after 3 s")

        let snapshot = recorder.snapshot
        let figures = Self.figures(snapshot.logs.values)
        for line in Self.landingLines(snapshot.logs.values) {
            note(line)
        }
        var report = TortureReport(
            number: number,
            label: label,
            rate: rate,
            seconds: seconds,
            conditions: conditions,
            requestCount: requestCount,
            taskCount: createdCount,
            startSpan: startSpan,
            cancelCount: cancelCount,
            cancelsWhileStarting: cancelsWhileStarting,
            drainDuration: drainDuration,
            unsettledCount: unsettled,
            aliveTaskCount: aliveTaskCount,
            tasksGoneAfter: tasksGoneAfter,
            queues: queues,
            fresh: fresh,
            pipelineReleasedAfter: pipelineReleasedAfter,
            loadCount: snapshot.loadCount,
            peakProcessingCount: snapshot.peakProcessingCount,
            figures: figures,
            violations: snapshot.violations,
            violationCount: snapshot.violationCount,
            log: lines
        )
        report.verdicts = Self.verdicts(for: report, logs: snapshot.logs.values)
        return report
    }

    // MARK: Pipeline

    private func makePipeline() {
        var configuration = ImagePipeline.Configuration(dataLoader: recorder.makeLoader(pace: Self.pace))
        configuration.imageCache = nil
        configuration.isProgressiveDecodingEnabled = true
        configuration.progressiveDecodingInterval = 0
        // A thousand records a run, and the probe times decoders only for a
        // pipeline that doesn't record them.
        configuration.isDiagnosticsEnabled = false
        pipeline = DemoPipelineProbe.makePipeline(label, configuration: configuration, delegate: TortureDelegate(recorder: recorder))
    }

    private var aliveTaskCount: Int {
        tasks.count { $0.task != nil }
    }

    private func currentQueues() -> TortureReport.Queues {
        let figures = pipeline.flatMap { DemoPipelineProbe.diagnostics(for: $0) } ?? DemoPipelineDiagnostics()
        return TortureReport.Queues(
            loading: figures.dataLoadingQueue.inFlightCount,
            loadingLimit: figures.dataLoadingQueue.limit,
            stuck: figures.cancelledInFlightDownloadCount,
            decoding: figures.decodingQueue.inFlightCount,
            decompressing: figures.decompressingQueue.inFlightCount,
            encoding: figures.encodingQueue.inFlightCount,
            processing: recorder.processingCount,
            activeTasks: figures.activeTaskCount,
            inFlightBytes: figures.inFlightByteCount
        )
    }

    /// Checks every 20 ms, and returns how long it took to hold, or `nil` if
    /// it didn't in time.
    private func waitUntil(timeout: Duration, _ condition: (TortureRun) -> Bool) async -> TimeInterval? {
        let start = clock.now
        guard await demoWait(timeout: timeout, until: { condition(self) }) else { return nil }
        return (clock.now - start).seconds
    }

    private func startFreshRequest() async -> TortureReport.Fresh {
        guard let pipeline else { return .timedOut(0) }
        let url = Self.url(of: .photo(0), query: URLQueryItem(name: "fresh", value: String(number)))
        let task = pipeline.imageTask(with: ImageRequest(url: url))
        let start = clock.now
        await demoWait(timeout: .seconds(5), every: .milliseconds(5)) { task.status.result != nil }
        let time = (clock.now - start).seconds
        switch task.status.result {
        case .success?:
            return .completed(time)
        case .failure(let error)?:
            return .failed(TortureOutcome(.failure(error)).title, time)
        case nil:
            task.cancel()
            return .timedOut(time)
        }
    }

    /// Cancels what is left and lets go of the pipeline.
    private func abandon() -> TortureReport? {
        for handle in handles.values {
            handle.task.cancel()
        }
        handles.removeAll()
        recorder.finishTriggers()
        pipeline = nil
        return nil
    }

    // MARK: Tasks

    /// Starts the tasks of one request: one, or two for a coalesced pair.
    private func startRequest(_ number: Int) {
        let kinds = TortureKind.allCases
        let points = TortureCancelPoint.allCases
        let apis = TortureAPI.allCases
        let kind = kinds[number % kinds.count]
        let point = points[(number / kinds.count) % points.count]
        let api = apis[(number / (kinds.count * points.count)) % apis.count]
        let request = makeRequest(kind, number: number)
        start(TortureTaskKey(unit: number), request, kind: kind, api: api, point: point)
        if kind == .coalesced {
            start(TortureTaskKey(unit: number, isPartner: true), request, kind: kind, api: api, point: nil)
        }
    }

    private func makeRequest(_ kind: TortureKind, number: Int) -> ImageRequest {
        let fixture = kind == .progressive ? DemoFixture.progressiveJPEG : .photo(number % Self.photoCount)
        // A URL of its own, so only the pairs meant to share a download do.
        let url = Self.url(of: fixture, query: URLQueryItem(name: TortureRecorder.unitQueryItem, value: String(number)))
        switch kind {
        case .plain, .progressive, .coalesced:
            return ImageRequest(url: url)
        case .processed:
            return ImageRequest(url: url, processors: [processor])
        case .thumbnail:
            var request = ImageRequest(url: url)
            request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 64)
            return request
        }
    }

    private static func url(of fixture: DemoFixture, query: URLQueryItem) -> URL {
        var components = URLComponents(url: fixture.url, resolvingAgainstBaseURL: false)
        components?.queryItems = [query]
        return components?.url ?? fixture.url
    }

    private func start(_ key: TortureTaskKey, _ request: ImageRequest, kind: TortureKind, api: TortureAPI, point: TortureCancelPoint?) {
        guard let pipeline else { return }
        var request = request
        request.userInfo[TortureTaskKey.userInfoKey] = key
        let recorder = recorder
        recorder.register(TortureTaskLog(key: key, kind: kind, api: api, point: point, createdAt: clock.now))

        let task: ImageTask
        var awaiting: Task<Void, Never>?
        switch api {
        case .events:
            task = pipeline.imageTask(with: request)
            Task { [weak self] in
                for await event in task.events {
                    recorder.streamEvent(key, event)
                }
                recorder.clientFinished(key, result: nil)
                self?.clientDidFinish(key)
            }
        case .response:
            task = pipeline.imageTask(with: request)
            awaiting = Task { [weak self] in
                let result: Result<ImageResponse, ImagePipeline.Error>
                do throws(ImagePipeline.Error) {
                    result = .success(try await task.response)
                } catch {
                    result = .failure(error)
                }
                recorder.clientFinished(key, result: result)
                self?.clientDidFinish(key)
            }
        case .closures:
            task = pipeline.loadImage(with: request, progress: { _, _, _ in
                recorder.closureCalled(key, result: nil)
            }, completion: { [weak self] result in
                recorder.closureCalled(key, result: result)
                self?.clientDidFinish(key)
            })
        }

        tasks.append(WeakTask(task: task))
        handles[key] = Handle(task: task, awaiting: awaiting)
        createdCount += 1
        let now = clock.now
        firstCreatedAt = firstCreatedAt ?? now
        lastCreatedAt = now

        switch point {
        case .immediately:
            cancel(key)
        case .soon:
            // Spread over 50 ms, the same way on every run.
            let delay = Duration.milliseconds((key.unit * 37) % 50)
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                self?.cancel(key)
            }
        default:
            break
        }
    }

    private func handle(_ trigger: TortureTrigger) {
        guard trigger.delay > .zero else {
            return cancel(trigger.key)
        }
        Task { [weak self] in
            try? await Task.sleep(for: trigger.delay)
            self?.cancel(trigger.key)
        }
    }

    /// The app has heard all it will: a partner is let go, and any other
    /// task still here is cancelled – the ones meant to be cancelled after
    /// finishing, and the ones whose moment never came.
    private func clientDidFinish(_ key: TortureTaskKey) {
        guard handles[key] != nil else { return }
        if key.isPartner {
            handles[key] = nil
        } else {
            cancel(key)
        }
    }

    private func cancel(_ key: TortureTaskKey) {
        guard let handle = handles.removeValue(forKey: key) else { return }
        let status = handle.task.status
        recorder.cancelRequested(key, status: status)
        cancelCount += 1
        if isStarting {
            cancelsWhileStarting += 1
        }
        if let awaiting = handle.awaiting, status.result == nil {
            // The pipeline cancels the image task when the Swift task that
            // awaits it is cancelled.
            awaiting.cancel()
        } else {
            handle.task.cancel()
        }
    }

    private func note(_ text: String) {
        lines.append(.init(id: lines.count, time: (clock.now - startedAt).seconds, text: text))
    }
}

// MARK: - Verdicts

extension TortureRun {
    private static func figures(_ logs: some Collection<TortureTaskLog>) -> TortureReport.Figures {
        var figures = TortureReport.Figures()
        for log in logs {
            if let landing = log.landing {
                figures.landings[landing, default: 0] += 1
            } else {
                figures.notCancelledCount += 1
            }
            figures.kinds[log.kind, default: .init()].add(log)
            figures.apis[log.api, default: .init()].add(log)
        }
        return figures
    }

    /// Where the cancels meant for each point landed, for the log.
    private static func landingLines(_ logs: some Collection<TortureTaskLog>) -> [String] {
        TortureCancelPoint.allCases.map { point in
            let landings = Dictionary(grouping: logs.filter { $0.point == point }.compactMap(\.landing), by: { $0 })
            let parts = TortureLanding.allCases.compactMap { landing in
                landings[landing].map { "\($0.count) \(landing.title)" }
            }
            return "cancel \(point.title): " + (parts.isEmpty ? "none" : parts.joined(separator: " · "))
        }
    }

    private static func verdicts(for report: TortureReport, logs: some Collection<TortureTaskLog>) -> [DemoVerdict] {
        var verdicts: [DemoVerdict] = []
        let cancelled = logs.filter(\.isCancelled)
        let hasFailuresOnPurpose = DemoNetworkConditions.current?.hasFailures ?? false

        // No callbacks after cancel
        let closuresAfterCancel = logs.reduce(0) { $0 + $1.closureCallsAfterCancel }
        let afterFinish = logs.reduce(0) { $0 + $1.eventsAfterFinish + $1.clientEventsAfterFinish }
        let callbacks = logs.reduce(0) { $0 + $1.eventCount + $1.clientEventCount + $1.closureCallCount }
        let inFlight = cancelled.filter { $0.eventsAfterCancel > 0 }
        let inFlightEvents = inFlight.reduce(0) { $0 + $1.eventsAfterCancel }
        let latestInFlight = inFlight.map(\.latestEventAfterCancel).max() ?? .zero
        verdicts.append(DemoVerdict(
            title: "No callbacks after cancel",
            state: closuresAfterCancel + afterFinish == 0 ? .passed : .failed,
            figures: "\(closuresAfterCancel + afterFinish) late · \(callbacks.formatted()) callbacks · \(cancelled.count.formatted()) cancels",
            detail: "Closures called after `cancel()`: \(closuresAfterCancel). Delegate and stream events after `.finished`: \(afterFinish). "
                + (inFlightEvents > 0
                    ? "\(inFlightEvents) progress or preview events of \(inFlight.count) tasks were already on their way when the app cancelled, the last \(TortureRecorder.format(latestInFlight)) after it: a cancel reaches the pipeline with a hop."
                    : "No event was on its way when the app cancelled.")
        ))

        // Every task finished once
        let never = logs.count { $0.finishCount == 0 || !$0.isDoneForClient }
        let twice = logs.count { $0.finishCount > 1 || $0.clientFinishCount > 1 || $0.completionCount > 1 }
        let mismatched = logs.count { log in log.clientResult.map { $0 != log.result } ?? false }
        let missingCompletion = logs.count { $0.api == .closures && !$0.isCancelled && $0.completionCount == 0 }
        let lateFinishes = cancelled.filter { $0.landing != .finished && $0.result != .cancelled }
        let lateLags = lateFinishes.compactMap { log in log.finishedAt.flatMap { finished in log.cancelledAt.map { finished - $0 } } }
        let ignored = lateLags.count { $0 > .seconds(1) }
        let broken = never + twice + mismatched + missingCompletion + ignored
        verdicts.append(DemoVerdict(
            title: "Every task finished once",
            state: broken == 0 ? .passed : .failed,
            figures: "\(logs.count { $0.finishCount == 1 }.formatted()) finished · \(twice) twice · \(never) never · \(mismatched) disagreed",
            detail: (lateFinishes.isEmpty
                ? "Every task cancelled before it finished ended cancelled."
                : "\(lateFinishes.count) tasks cancelled before they finished ended anyway, the last \(TortureRecorder.format(lateLags.max() ?? .zero)) after the cancel: the pipeline already had the result.")
                + (ignored > 0 ? " \(ignored) ended more than a second after it, which is a cancel ignored." : "")
                + (missingCompletion > 0 ? " \(missingCompletion) closures never heard of a task that wasn't cancelled." : " The delegate, the streams, the responses, and the closures heard the same outcome.")
        ))

        // No surviving ImageTask
        verdicts.append(DemoVerdict(
            title: "No ImageTask left",
            state: report.aliveTaskCount == 0 ? .passed : .failed,
            figures: "\(report.aliveTaskCount) of \(report.taskCount.formatted()) alive",
            detail: report.tasksGoneAfter.map { "Held weakly by the run; all were gone \(tortureDuration($0)) after the last one had finished." }
                ?? "Held weakly by the run; \(report.aliveTaskCount) were still there 2 s after the last one finished."
        ))

        // Queues back to zero
        let queues = report.queues
        func count(_ value: Int?) -> String { value.map(String.init) ?? "–" }
        verdicts.append(DemoVerdict(
            title: "Queues back to zero",
            state: queues.isIdle ? .passed : .failed,
            figures: "load \(count(queues.loading))/\(queues.loadingLimit) · stuck \(queues.stuck) · decode \(count(queues.decoding)) · decompress \(count(queues.decompressing)) · process \(queues.processing) · tasks \(queues.activeTasks)",
            detail: (queues.settledAfter.map { "Idle \(tortureDuration($0)) after the tasks were gone." } ?? "Still busy 2 s after the tasks were gone.")
                + " The probe counts the downloads, decodes, and decompressions in flight, and the run's own processor the processing (\(report.peakProcessingCount) at most at once). `tasks` is the probe's count of tasks not yet finished. What waits in a queue can't be seen from outside Nuke."
        ))

        // Survivors
        let survivors = logs.filter { !$0.isCancelled || $0.landing == .finished }
        let survivorImages = survivors.count { $0.result == .image }
        let survivorFailures = Dictionary(grouping: survivors.compactMap { log -> String? in
            if case .failed(let name)? = log.result { name } else { nil }
        }, by: { $0 })
        verdicts.append(DemoVerdict(
            title: "Survivors got their image",
            state: survivorImages == survivors.count ? .passed : hasFailuresOnPurpose ? .skipped : .failed,
            figures: "\(survivorImages) of \(survivors.count) · \(survivors.count - survivorImages) failed",
            detail: "The second task of every coalesced pair, whose download went on when the first was cancelled, and every task that finished before its cancel."
                + (survivorFailures.isEmpty ? "" : " Failed: " + survivorFailures.map { "\($0.value.count) \($0.key)" }.sorted().joined(separator: ", ") + ".")
                + (hasFailuresOnPurpose ? " The network conditions fail downloads on purpose, so failures don't count." : "")
        ))

        // A new request
        let fresh: (DemoVerdict.State, String, String) = switch report.fresh {
        case .completed(let time): (.passed, "completed in \(tortureDuration(time))", "A photo nothing in the run asked for, on the same pipeline, once the queues were idle.")
        case let .failed(error, time): (hasFailuresOnPurpose ? .skipped : .failed, "failed in \(tortureDuration(time))", "It failed with `\(error)`.")
        case .timedOut(let time): (.failed, "not done in \(tortureDuration(time))", "It never finished: something still holds what it needs.")
        }
        verdicts.append(DemoVerdict(title: "A new request completes", state: fresh.0, figures: fresh.1, detail: fresh.2))

        // The pipeline goes away
        verdicts.append(DemoVerdict(
            title: "Pipeline released",
            state: report.pipelineReleasedAfter == nil ? .failed : .passed,
            figures: report.pipelineReleasedAfter.map { "gone after \(tortureDuration($0))" } ?? "alive after 3 s",
            detail: "Held weakly once the run let go of it. Work that never ends – a download whose slot was never given back – keeps a pipeline alive."
        ))

        // The rate
        let actualRate = report.startSpan > 0 ? Double(report.taskCount - 1) / report.startSpan : 0
        let pairs = report.taskCount - report.requestCount
        verdicts.append(DemoVerdict(
            title: "Started at \(report.rate)/s",
            state: abs(actualRate - Double(report.rate)) <= Double(report.rate) * 0.05 ? .passed : .failed,
            figures: "\(report.taskCount.formatted()) tasks in \(String(format: "%.2fs", report.startSpan)) · \(String(format: "%.1f", actualRate))/s",
            detail: "\(report.requestCount.formatted()) requests, \(pairs) of them asked for twice. \(report.cancelCount.formatted()) cancels, \(report.cancelsWhileStarting.formatted()) of them while tasks were still starting; the rest waited for a load or an image. Every task had finished \(demoSeconds(report.drainDuration)) after the last one started."
        ))
        return verdicts
    }
}

// MARK: - Slot Check

/// Takes every data loading slot of a pipeline with downloads that last a
/// second, cancels them all midway, and asks for one more image: does the
/// pipeline ask its delegate for a loader for it?
///
/// With a loader that calls `completion` after a cancel, it does at once.
/// With one that follows the documentation of `DataLoading` and calls
/// nothing, it never does: the pipeline gives a slot back when the loader
/// calls `completion`, and on nothing else, and the unfinished work holds
/// the pipeline too. That second pipeline is never released; the HUD keeps
/// listing it, with its slots taken. It is a Nuke issue, not the demo's.
///
/// Only public API is used to tell: the delegate's `dataLoader(for:)`.
@MainActor
enum SlotCheck {
    struct Result: Identifiable, Sendable {
        let completesCancelledLoads: Bool
        let label: String
        /// The data loading queue's slots, all of which the check takes.
        let slotCount: Int
        /// The downloads that had data when they were cancelled.
        let cancelledMidBody: Int
        /// The downloads the probe counts in flight after the cancels.
        let heldSlots: Int?
        /// Of those, the ones cancelled whose loader hasn't completed.
        let stuckCount: Int
        /// From the new request to the delegate being asked for its loader,
        /// or `nil` if it wasn't within ``timeout``.
        let dataLoaderAfter: TimeInterval?
        /// From the new request to its image, or `nil`.
        let completedAfter: TimeInterval?
        /// `nil` if the pipeline was still there after 2 s.
        let releasedAfter: TimeInterval?
        let timeout: TimeInterval

        var id: Bool { completesCancelledLoads }
    }

    static let silentLabel = "Cancellation Torture · Silent Loader"

    /// `nil` if it was cancelled.
    static func run(completesCancelledLoads: Bool, number: Int) async -> Result? {
        let clock = ContinuousClock()
        let timeout = Duration.seconds(2)
        let calls = LoaderCalls()
        let label = completesCancelledLoads ? "Cancellation Torture · Completing Loader \(number)" : "\(silentLabel) \(number)"
        // A second a download, in twenty chunks.
        let loader = DemoFixtureLoader(pace: .chunks(20, interval: .milliseconds(50)), completesCancelledLoads: completesCancelledLoads)
        var configuration = ImagePipeline.Configuration(dataLoader: loader)
        configuration.imageCache = nil
        let slotCount = configuration.dataLoadingQueue.maxConcurrentTaskCount

        var pipeline: ImagePipeline? = DemoPipelineProbe.makePipeline(label, configuration: configuration, delegate: SlotDelegate(calls: calls))
        weak var releasedPipeline: ImagePipeline?
        releasedPipeline = pipeline

        func url(_ index: Int, _ name: String) -> URL {
            var components = URLComponents(url: DemoFixture.photo(index).url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "slots", value: "\(number)-\(name)")]
            return components?.url ?? DemoFixture.photo(index).url
        }

        // Every slot, until each download has some data.
        let tasks = (0..<slotCount).compactMap { index in
            pipeline?.imageTask(with: ImageRequest(url: url(index, String(index))))
        }
        await demoWait(timeout: .seconds(3), every: .milliseconds(10)) {
            !tasks.contains { $0.status.progress.completed == 0 }
        }
        let cancelledMidBody = tasks.count { $0.status.progress.completed > 0 && $0.status.result == nil }
        for task in tasks {
            task.cancel()
        }
        // Long enough for a loader that completes to have done it.
        try? await Task.sleep(for: .milliseconds(200))
        let figures = pipeline.flatMap { DemoPipelineProbe.diagnostics(for: $0) }

        // One more.
        let freshURL = url(slotCount, "fresh")
        let fresh = pipeline?.imageTask(with: ImageRequest(url: freshURL))
        let freshStart = clock.now
        var dataLoaderAfter: TimeInterval?
        while clock.now - freshStart < timeout, !Task.isCancelled {
            if let calledAt = calls.calledAt(freshURL) {
                dataLoaderAfter = (calledAt - freshStart).seconds
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        var completedAfter: TimeInterval?
        if dataLoaderAfter != nil {
            await demoWait(timeout: .seconds(5) - (clock.now - freshStart), every: .milliseconds(10)) { fresh?.status.result != nil }
            if case .success? = fresh?.status.result {
                completedAfter = (clock.now - freshStart).seconds
            }
        }
        fresh?.cancel()
        guard !Task.isCancelled else { return nil }

        pipeline = nil
        let releaseStart = clock.now
        var releasedAfter: TimeInterval?
        if await demoWait(timeout: timeout, until: { releasedPipeline == nil }) {
            releasedAfter = (clock.now - releaseStart).seconds
        }

        return Result(
            completesCancelledLoads: completesCancelledLoads,
            label: label,
            slotCount: slotCount,
            cancelledMidBody: cancelledMidBody,
            heldSlots: figures?.dataLoadingQueue.inFlightCount,
            stuckCount: figures?.cancelledInFlightDownloadCount ?? 0,
            dataLoaderAfter: dataLoaderAfter,
            completedAfter: completedAfter,
            releasedAfter: releasedAfter,
            timeout: timeout.seconds
        )
    }
}

/// When the delegate was asked for a loader, by URL.
private final class LoaderCalls: Sendable {
    private let calls = OSAllocatedUnfairLock(initialState: [URL: ContinuousClock.Instant]())

    func record(_ url: URL?) {
        guard let url else { return }
        let now = ContinuousClock.now
        calls.withLock { $0[url] = now }
    }

    func calledAt(_ url: URL) -> ContinuousClock.Instant? {
        calls.withLock { $0[url] }
    }
}

/// The delegate's `dataLoader(for:)`: the pipeline calls it once a
/// download has a slot, just before it starts.
private final class SlotDelegate: ImagePipeline.Delegate {
    private let calls: LoaderCalls

    init(calls: LoaderCalls) {
        self.calls = calls
    }

    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading {
        calls.record(request.url)
        return pipeline.configuration.dataLoader
    }
}

extension Duration {
    fileprivate var seconds: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import os

// What a run of Cancellation Torture asks for, and what it hears back: the
// mix of requests, the record of every task, and the delegate that listens
// to the pipeline.

/// The kinds of request a run mixes, one after the other.
enum TortureKind: CaseIterable, Hashable, Sendable {
    /// A photo, as is.
    case plain
    /// A photo through a resize processor, which also counts the work in
    /// flight on the processing queue: the probe can't see that queue.
    case processed
    /// A photo decoded as a 64 px thumbnail, on the decoding queue.
    case thumbnail
    /// The progressive JPEG, whose scans arrive one per chunk, each decoded
    /// into a preview.
    case progressive
    /// The same photo asked for twice at once, so both tasks share one
    /// download. Only the first is cancelled; the second has to get its
    /// image.
    case coalesced

    var title: String {
        switch self {
        case .plain: "plain"
        case .processed: "processed"
        case .thumbnail: "thumbnail"
        case .progressive: "progressive"
        case .coalesced: "coalesced"
        }
    }
}

/// How the app listens to a task: each is a different path out of the
/// pipeline, with a different promise about cancellation.
enum TortureAPI: CaseIterable, Hashable, Sendable {
    /// `for await event in task.events`, cancelled with `task.cancel()`.
    case events
    /// `try await task.response`, cancelled by cancelling the Swift task
    /// that awaits it.
    case response
    /// `pipeline.loadImage(with:progress:completion:)`, whose closures are
    /// never called after `cancel()`.
    case closures

    var title: String {
        switch self {
        case .events: "events"
        case .response: "response"
        case .closures: "closures"
        }
    }
}

/// When a run cancels a task.
enum TortureCancelPoint: CaseIterable, Hashable, Sendable {
    /// Right after creating it, before the pipeline has started it.
    case immediately
    /// Up to 50 ms after creating it, wherever that lands.
    case soon
    /// Halfway through the fixture's latency, once its load has started.
    case inLatency
    /// At the first chunk of data, or the first preview of the progressive
    /// JPEG.
    case midBody
    /// Once the app has heard that it finished: a cancel that should change
    /// nothing.
    case afterFinish

    var title: String {
        switch self {
        case .immediately: "at once"
        case .soon: "within 50 ms"
        case .inLatency: "in the latency"
        case .midBody: "mid-body"
        case .afterFinish: "after finishing"
        }
    }
}

/// Where a task was when the app asked to cancel it, read from its status
/// and the loads the run saw start.
enum TortureLanding: CaseIterable, Hashable, Sendable {
    /// The pipeline hadn't started it.
    case notStarted
    /// Started, with its download waiting for the rate limiter or a slot.
    case queued
    /// Its download had started and had no bytes yet.
    case connecting
    /// Part of the data was in.
    case receiving
    /// All of the data was in, and the image wasn't ready.
    case decoding
    /// It had finished.
    case finished

    var title: String {
        switch self {
        case .notStarted: "before it started"
        case .queued: "queued"
        case .connecting: "in the latency"
        case .receiving: "mid-body"
        case .decoding: "after the last byte"
        case .finished: "after it finished"
        }
    }
}

/// How a task ended, without the image.
enum TortureOutcome: Hashable, Sendable {
    case image
    case cancelled
    case failed(String)

    init(_ result: Result<ImageResponse, ImagePipeline.Error>) {
        switch result {
        case .success: self = .image
        case .failure(.cancelled): self = .cancelled
        case .failure(let error): self = .failed(Self.name(of: error))
        }
    }

    var title: String {
        switch self {
        case .image: "image"
        case .cancelled: "cancelled"
        case .failed(let name): name
        }
    }

    /// The name of the case, without its payload.
    private static func name(of error: ImagePipeline.Error) -> String {
        switch error {
        case .dataMissingInCache: "dataMissingInCache"
        case .dataLoadingFailed: "dataLoadingFailed"
        case .dataIsEmpty: "dataIsEmpty"
        case .decoderNotRegistered: "decoderNotRegistered"
        case .decodingFailed: "decodingFailed"
        case .processingFailed: "processingFailed"
        case .imageRequestMissing: "imageRequestMissing"
        case .pipelineInvalidated: "pipelineInvalidated"
        case .dataDownloadExceededMaximumSize: "dataDownloadExceededMaximumSize"
        case .cancelled: "cancelled"
        @unknown default: "unknown"
        }
    }
}

/// Which task of a run a request belongs to, carried in its `userInfo`:
/// neither the caches nor coalescing look at it.
struct TortureTaskKey: Hashable, Sendable, CustomStringConvertible {
    /// The request's number in the run.
    let unit: Int
    /// The second task of a coalesced pair, which is never cancelled.
    let isPartner: Bool

    static let userInfoKey: ImageRequest.UserInfoKey = "com.github.kean.NukeDemo.CancellationTorture"

    init(unit: Int, isPartner: Bool = false) {
        self.unit = unit
        self.isPartner = isPartner
    }

    init?(_ request: ImageRequest) {
        guard let key = request.userInfo[Self.userInfoKey] as? TortureTaskKey else { return nil }
        self = key
    }

    var description: String {
        isPartner ? "#\(unit)b" : "#\(unit)"
    }
}

/// Everything a run heard about one task.
struct TortureTaskLog: Sendable {
    let key: TortureTaskKey
    let kind: TortureKind
    let api: TortureAPI
    /// `nil` for a coalesced partner, which is never cancelled.
    let point: TortureCancelPoint?
    let createdAt: ContinuousClock.Instant

    /// `imageTaskDidStart`.
    var startedAt: ContinuousClock.Instant?
    /// When the app asked to cancel it.
    var cancelledAt: ContinuousClock.Instant?
    var landing: TortureLanding?
    /// Whether the event it waits for to be cancelled has come.
    var isTriggered = false

    // The delegate's events, in the order the pipeline sent them.

    var eventCount = 0
    var previewCount = 0
    var finishCount = 0
    var finishedAt: ContinuousClock.Instant?
    var result: TortureOutcome?
    /// Events after `.finished`: none, ever.
    var eventsAfterFinish = 0
    /// Progress and previews sent after the app asked to cancel, before the
    /// pipeline acted on it: allowed, since a cancel reaches the pipeline
    /// with a hop.
    var eventsAfterCancel = 0
    var latestEventAfterCancel: Duration = .zero

    // What the app's side heard.

    /// Stream events, or the one response.
    var clientEventCount = 0
    var clientFinishCount = 0
    var clientEventsAfterFinish = 0
    var clientResult: TortureOutcome?
    /// Closure calls, the completion included.
    var closureCallCount = 0
    /// Closure calls after `cancel()`: none, ever – the closures are called
    /// on the main thread, where the cancel is made, and not after it.
    var closureCallsAfterCancel = 0
    var completionCount = 0

    var isCancelled: Bool { cancelledAt != nil }

    /// Whether the app has heard all it will hear of the task.
    var isDoneForClient: Bool {
        switch api {
        case .events, .response: clientFinishCount > 0
        case .closures: completionCount > 0 || isCancelled
        }
    }

    var isSettled: Bool {
        finishCount > 0 && isDoneForClient
    }
}

/// A task to cancel, after a wait: what the delegate and the loader ask of
/// the run, which cancels on the main thread, as an app does.
struct TortureTrigger: Sendable {
    let key: TortureTaskKey
    var delay: Duration = .zero
}

/// The record of a run, written from the pipeline's threads and the main
/// thread under one lock.
final class TortureRecorder: Sendable {
    let triggers: AsyncStream<TortureTrigger>
    private let continuation: AsyncStream<TortureTrigger>.Continuation
    /// Half of the fixture's latency: when an `inLatency` cancel is made.
    private let latencyCancelDelay: Duration
    private let state = OSAllocatedUnfairLock(initialState: State())

    struct State: Sendable {
        var logs: [TortureTaskKey: TortureTaskLog] = [:]
        /// The requests whose download has started.
        var loadedUnits: Set<Int> = []
        var loadCount = 0
        var processingCount = 0
        var peakProcessingCount = 0
        /// The first few breaches, described.
        var violations: [String] = []
        var violationCount = 0
    }

    init(latency: Duration) {
        (triggers, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        latencyCancelDelay = latency / 2
    }

    func finishTriggers() {
        continuation.finish()
    }

    var snapshot: State {
        state.withLock { $0 }
    }

    /// The tasks that haven't finished, or whose app side hasn't heard all
    /// it will.
    var unsettledCount: Int {
        state.withLock { $0.logs.values.count { !$0.isSettled } }
    }

    var processingCount: Int {
        state.withLock { $0.processingCount }
    }

    // MARK: Main Thread

    func register(_ log: TortureTaskLog) {
        state.withLock { $0.logs[log.key] = log }
    }

    /// The app asks to cancel: where the task is now, from its status.
    func cancelRequested(_ key: TortureTaskKey, status: ImageTask.Status) {
        let now = ContinuousClock.now
        state.withLock { state in
            guard var log = state.logs[key], log.cancelledAt == nil else { return }
            log.cancelledAt = now
            log.landing = if status.result != nil {
                .finished
            } else if status.progress.completed == 0 {
                if state.loadedUnits.contains(key.unit) {
                    .connecting
                } else {
                    log.startedAt == nil ? .notStarted : .queued
                }
            } else if status.progress.completed < status.progress.total {
                .receiving
            } else {
                .decoding
            }
            state.logs[key] = log
        }
    }

    func streamEvent(_ key: TortureTaskKey, _ event: ImageTask.Event) {
        state.withLock { state in
            guard var log = state.logs[key] else { return }
            log.clientEventCount += 1
            if log.clientFinishCount > 0 {
                log.clientEventsAfterFinish += 1
                state.breach("\(log.summary): a stream event after .finished")
            }
            if case .finished(let result) = event {
                log.clientFinishCount += 1
                log.clientResult = TortureOutcome(result)
            }
            state.logs[key] = log
        }
    }

    /// The stream ended, or the awaited response returned.
    func clientFinished(_ key: TortureTaskKey, result: Result<ImageResponse, ImagePipeline.Error>?) {
        state.withLock { state in
            guard var log = state.logs[key] else { return }
            if let result {
                log.clientEventCount += 1
                log.clientFinishCount += 1
                log.clientResult = TortureOutcome(result)
            } else if log.clientFinishCount == 0 {
                state.breach("\(log.summary): the stream ended without .finished")
                log.clientFinishCount = 1
            }
            state.logs[key] = log
        }
    }

    /// A progress or completion closure was called.
    func closureCalled(_ key: TortureTaskKey, result: Result<ImageResponse, ImagePipeline.Error>?) {
        let now = ContinuousClock.now
        state.withLock { state in
            guard var log = state.logs[key] else { return }
            log.closureCallCount += 1
            if let cancelledAt = log.cancelledAt {
                log.closureCallsAfterCancel += 1
                state.breach("\(log.summary): a closure called \(Self.format(now - cancelledAt)) after cancel()")
            }
            if let result {
                log.completionCount += 1
                log.clientResult = TortureOutcome(result)
                if log.completionCount > 1 {
                    state.breach("\(log.summary): the completion called twice")
                }
            }
            state.logs[key] = log
        }
    }

    // MARK: Pipeline

    fileprivate func didStart(_ key: TortureTaskKey) {
        let now = ContinuousClock.now
        state.withLock { $0.logs[key]?.startedAt = now }
    }

    fileprivate func delegateEvent(_ key: TortureTaskKey, _ event: ImageTask.Event) {
        let now = ContinuousClock.now
        let trigger = state.withLock { state -> TortureTrigger? in
            guard var log = state.logs[key] else { return nil }
            defer { state.logs[key] = log }
            log.eventCount += 1
            if log.finishCount > 0 {
                log.eventsAfterFinish += 1
                state.breach("\(log.summary): a delegate event after .finished")
            }
            switch event {
            case .finished(let result):
                log.finishCount += 1
                log.finishedAt = now
                log.result = TortureOutcome(result)
                return nil
            case .progress(let progress):
                log.noteAfterCancel(at: now)
                let isMidBody = progress.completed > 0 && progress.completed < progress.total
                guard log.point == .midBody, log.kind != .progressive, isMidBody, !log.isTriggered else { return nil }
                log.isTriggered = true
                return TortureTrigger(key: key)
            case .preview:
                log.previewCount += 1
                log.noteAfterCancel(at: now)
                guard log.point == .midBody, log.kind == .progressive, !log.isTriggered else { return nil }
                log.isTriggered = true
                return TortureTrigger(key: key)
            }
        }
        if let trigger {
            continuation.yield(trigger)
        }
    }

    /// A fixture load started: its request's number is in the URL.
    fileprivate func loadStarted(_ url: URL?) {
        guard let unit = url.flatMap(Self.unit(of:)) else { return }
        let key = TortureTaskKey(unit: unit)
        let trigger = state.withLock { state -> TortureTrigger? in
            state.loadCount += 1
            state.loadedUnits.insert(unit)
            guard var log = state.logs[key], log.point == .inLatency, !log.isTriggered else { return nil }
            log.isTriggered = true
            state.logs[key] = log
            return TortureTrigger(key: key, delay: latencyCancelDelay)
        }
        if let trigger {
            continuation.yield(trigger)
        }
    }

    fileprivate func processingStarted() {
        state.withLock { state in
            state.processingCount += 1
            state.peakProcessingCount = max(state.peakProcessingCount, state.processingCount)
        }
    }

    fileprivate func processingFinished() {
        state.withLock { $0.processingCount -= 1 }
    }

    /// The query item every request of a run carries.
    static let unitQueryItem = "n"

    private static func unit(of url: URL) -> Int? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == unitQueryItem }?
            .value.flatMap { Int($0) }
    }

    static func format(_ duration: Duration) -> String {
        tortureDuration(duration.demoTimeInterval)
    }
}

/// A span from microseconds to seconds, the way the torture's figures write
/// it: what rounds to 0 ms reads as under a millisecond.
func tortureDuration(_ value: TimeInterval) -> String {
    value < 0.0005 ? "under 1ms" : demoDuration(value)
}

extension TortureRecorder.State {
    fileprivate mutating func breach(_ description: String) {
        violationCount += 1
        if violations.count < 20 {
            violations.append(description)
        }
    }
}

extension TortureTaskLog {
    fileprivate mutating func noteAfterCancel(at now: ContinuousClock.Instant) {
        guard let cancelledAt else { return }
        eventsAfterCancel += 1
        latestEventAfterCancel = max(latestEventAfterCancel, now - cancelledAt)
    }

    /// The task, as a log line names it.
    var summary: String {
        [key.description, kind.title, api.title, point.map { "cancel \($0.title)" } ?? "kept"].joined(separator: " · ")
    }
}

// MARK: - Delegate

/// Hears every task of a run through the pipeline's delegate: when it
/// starts, and every event it sends, in order.
final class TortureDelegate: ImagePipeline.Delegate {
    private let recorder: TortureRecorder

    init(recorder: TortureRecorder) {
        self.recorder = recorder
    }

    @ImagePipelineActor
    func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {
        guard let key = TortureTaskKey(task.request) else { return }
        recorder.didStart(key)
    }

    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard let key = TortureTaskKey(task.request) else { return }
        recorder.delegateEvent(key, event)
    }
}

// MARK: - Requests

extension TortureRecorder {
    /// A fixture loader that tells the recorder when each load starts.
    func makeLoader(pace: DemoFixtureLoader.Pace) -> DemoFixtureLoader {
        DemoFixtureLoader(pace: pace, hooks: DemoLoadHooks(didStart: { [weak self] load in
            self?.loadStarted(load.request.url)
        }))
    }

    /// A resize processor that counts the images it is processing.
    func makeProcessor() -> ImageProcessors.Anonymous {
        let resize = ImageProcessors.Resize(width: 64)
        return ImageProcessors.Anonymous(id: "com.github.kean.NukeDemo.CancellationTorture.resize") { [weak self] image in
            self?.processingStarted()
            defer { self?.processingFinished() }
            return resize.process(image)
        }
    }
}

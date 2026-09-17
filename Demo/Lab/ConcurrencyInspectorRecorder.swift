// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import os
import QuartzCore

// What a workload of the Concurrency Inspector asks the pipeline for, and
// what the screen hears back: the record of every task and of the work behind
// each request, written by the delegate and the decorators it hands the
// pipeline, and read ten times a second.

/// The kinds of request a workload mixes. Each takes its own path through the
/// queues.
enum InspectorKind: Hashable, Sendable {
    /// A photo, decoded on the pipeline's actor as its data arrives, then
    /// decompressed on the decompressing queue.
    case photo
    /// A photo resized and blurred on the processing queue, then encoded for
    /// the disk cache on the encoding queue.
    case blurred
    /// A photo decoded as a 64 px thumbnail on the decoding queue, then
    /// encoded.
    case thumbnail
    /// The 12 MP JPEG as a 480 px thumbnail: a long decode on the decoding
    /// queue, then an encode.
    case largeThumbnail
    /// The 12 MP JPEG in full: a quick decode, then the longest
    /// decompression, of a 46 MB bitmap.
    case large
    /// A photo asked for twice at once: two tasks, and one download, one
    /// decode, and one decompression between them.
    case pair

    /// Six characters at most, for a column.
    var title: String {
        switch self {
        case .photo: "photo"
        case .blurred: "blur"
        case .thumbnail: "thumb"
        case .largeThumbnail: "12mp·t"
        case .large: "12mp"
        case .pair: "pair"
        }
    }

    /// Whether its decode waits for the decoding queue. `ImageDecoders.Default`
    /// asks for the queue only for a thumbnail; any other decode runs on the
    /// pipeline's actor as soon as the data is in.
    var decodesOnQueue: Bool {
        self == .thumbnail || self == .largeThumbnail
    }

    var isProcessed: Bool {
        self == .blurred
    }

    /// The fixture of the request with this number.
    func fixture(unit: Int) -> DemoFixture {
        switch self {
        case .large, .largeThumbnail: .largeJPEG
        default: .photo(unit % DemoFixture.photos.count)
        }
    }
}

/// Where a task is, from the events of its own and of the work behind its
/// request. The order is the order a task goes through them.
enum InspectorState: Int, CaseIterable, Comparable, Sendable {
    /// Created, and the pipeline hasn't started it.
    case notStarted
    /// Started, with its download waiting for the rate limiter or a data
    /// loading slot.
    case queued
    /// Its loader was called and hasn't sent a byte.
    case loading
    /// Part of the data is in.
    case receiving
    /// The data is in, and the decode waits for the decoding queue.
    case decodeWaiting
    /// Decoding: on the decoding queue, or on the pipeline's actor.
    case decoding
    case processWaiting
    case processing
    case decompressWaiting
    case decompressing
    /// Finished with an image.
    case image
    case cancelled
    case failed

    var title: String {
        switch self {
        case .notStarted: "created"
        case .queued: "queued"
        case .loading: "loading"
        case .receiving: "receiving"
        case .decodeWaiting: "decode wait"
        case .decoding: "decoding"
        case .processWaiting: "process wait"
        case .processing: "processing"
        case .decompressWaiting: "decomp wait"
        case .decompressing: "decompressing"
        case .image: "image"
        case .cancelled: "cancelled"
        case .failed: "failed"
        }
    }

    /// Not finished.
    var isActive: Bool {
        self < .image
    }

    /// Waiting for something to start it rather than being worked on.
    var isWaiting: Bool {
        switch self {
        case .notStarted, .queued, .decodeWaiting, .processWaiting, .decompressWaiting: true
        default: false
        }
    }

    static func < (lhs: InspectorState, rhs: InspectorState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The task queues of a pipeline.
enum InspectorQueue: CaseIterable, Hashable, Sendable {
    case dataLoading
    case decoding
    case processing
    case decompressing
    case encoding

    var title: String {
        switch self {
        case .dataLoading: "Data Loading"
        case .decoding: "Decoding"
        case .processing: "Processing"
        case .decompressing: "Decompressing"
        case .encoding: "Encoding"
        }
    }

    /// For a column.
    var shortTitle: String {
        switch self {
        case .dataLoading: "load"
        case .decoding: "decode"
        case .processing: "process"
        case .decompressing: "decomp"
        case .encoding: "encode"
        }
    }

    func queue(in configuration: ImagePipeline.Configuration) -> TaskQueue {
        switch self {
        case .dataLoading: configuration.dataLoadingQueue
        case .decoding: configuration.imageDecodingQueue
        case .processing: configuration.imageProcessingQueue
        case .decompressing: configuration.imageDecompressingQueue
        case .encoding: configuration.imageEncodingQueue
        }
    }

    func figures(in diagnostics: DemoPipelineDiagnostics) -> DemoPipelineDiagnostics.Queue {
        switch self {
        case .dataLoading: diagnostics.dataLoadingQueue
        case .decoding: diagnostics.decodingQueue
        case .processing: diagnostics.processingQueue
        case .decompressing: diagnostics.decompressingQueue
        case .encoding: diagnostics.encodingQueue
        }
    }
}

/// Which task of a run a request belongs to, carried in its `userInfo`,
/// which neither the caches nor coalescing look at. A job the pipeline
/// creates keeps the request of the task that created it, so the work behind
/// a request is found by it too.
struct InspectorTaskKey: Hashable, Sendable {
    /// The task's number in the run, from 0: where it is in the record.
    let index: Int
    /// The request's number in the run. The two tasks of a pair share it.
    let unit: Int
    /// The second task of a pair.
    let isPartner: Bool

    static let userInfoKey: ImageRequest.UserInfoKey = "com.github.kean.NukeDemo.ConcurrencyInspector"

    init(index: Int, unit: Int, isPartner: Bool) {
        self.index = index
        self.unit = unit
        self.isPartner = isPartner
    }

    init?(_ request: ImageRequest) {
        guard let key = request.userInfo[Self.userInfoKey] as? InspectorTaskKey else { return nil }
        self = key
    }

    var title: String {
        isPartner ? "#\(unit)b" : "#\(unit)"
    }
}

/// A task of a run, as the screen heard of it.
struct InspectorTaskRecord: Sendable {
    let key: InspectorTaskKey
    let kind: InspectorKind
    let createdAt: CFTimeInterval
    var priority: ImageRequest.Priority
    /// `imageTaskDidStart`.
    var startedAt: CFTimeInterval?
    /// The `.finished` event.
    var finishedAt: CFTimeInterval?
    var outcome: Outcome?

    enum Outcome: Sendable, Equatable {
        case image
        case cancelled
        case failed(String)
    }
}

/// The work behind one request of a run: its download, decode, processing,
/// and decompression. The tasks of a pair share it.
struct InspectorJobRecord: Sendable {
    let kind: InspectorKind
    /// When the first of its tasks started. From then on its download waits
    /// for the rate limiter and a data loading slot.
    var startedAt: CFTimeInterval?
    var loadStartedAt: CFTimeInterval?
    var loadEndedAt: CFTimeInterval?
    var isLoadFailed = false
    var receivedByteCount: Int64 = 0
    /// The response's `expectedContentLength`, or 0 until a response came.
    var expectedByteCount: Int64 = 0
    var decodeStartedAt: CFTimeInterval?
    var decodeEndedAt: CFTimeInterval?
    var processStartedAt: CFTimeInterval?
    var decompressQueuedAt: CFTimeInterval?
    var decompressStartedAt: CFTimeInterval?
}

/// How long work waited for a queue before it started.
struct InspectorWait: Sendable, Equatable {
    var count = 0
    var total: TimeInterval = 0
    var max: TimeInterval = 0

    var average: TimeInterval {
        count > 0 ? total / Double(count) : 0
    }

    mutating func record(_ wait: TimeInterval) {
        count += 1
        total += wait
        max = Swift.max(max, wait)
    }
}

/// A run's figures for one queue, as the screen sees them.
struct InspectorQueueFigures: Sendable, Equatable {
    /// The run's work waiting for the queue. Tracked by the screen, request
    /// by request: the queue keeps its own count to itself.
    var waiting = 0
    /// The run's work on the queue now, from the decorators' calls.
    var running = 0
    var wait = InspectorWait()
}

/// A task, as a row of the list shows it.
struct InspectorRow: Identifiable, Sendable, Equatable {
    let key: InspectorTaskKey
    let kind: InspectorKind
    let priority: ImageRequest.Priority
    let state: InspectorState
    /// The share of the data in, while it arrives.
    let fraction: Double?
    /// Since the task was created; for a finished one, how long it took.
    let age: TimeInterval
    let failure: String?

    var id: Int { key.index }
}

/// A run's record, read in one go.
struct InspectorSample: Sendable, Equatable {
    var time: CFTimeInterval = 0
    /// The tasks the run created, the ones the record no longer keeps
    /// included.
    var taskCount = 0
    var requestCount = 0
    /// The tasks in each state, by `InspectorState.rawValue`. The finished
    /// ones include the tasks the record no longer keeps.
    var counts = [Int](repeating: 0, count: InspectorState.allCases.count)
    /// The states of the last ``InspectorRecorder/cellLimit`` tasks, oldest
    /// first.
    var cells: [InspectorState] = []
    /// The unfinished tasks, oldest first, up to a limit.
    var active: [InspectorRow] = []
    /// The unfinished tasks past the limit.
    var hiddenActiveCount = 0
    /// The last tasks to finish, newest first.
    var finished: [InspectorRow] = []
    var queues: [InspectorQueue: InspectorQueueFigures] = [:]
    /// How long the sample took to read, lock included.
    var duration: TimeInterval = 0

    func count(_ state: InspectorState) -> Int {
        counts[state.rawValue]
    }

    var activeCount: Int {
        InspectorState.allCases.filter(\.isActive).reduce(0) { $0 + counts[$1.rawValue] }
    }
}

/// The record of a run, written from the pipeline's threads and the main
/// thread under one lock.
///
/// Reading it builds the rows and counts inside the lock rather than copying
/// the record out: a copy would be thrown away at once, and the next write
/// would have to copy the arrays again.
final class InspectorRecorder: Sendable {
    /// The most tasks the map shows.
    static let cellLimit = 400
    /// The most unfinished tasks the list shows.
    static let activeRowLimit = 40
    /// The most finished tasks the list shows.
    static let finishedRowLimit = 20

    private let state = OSAllocatedUnfairLock(initialState: State())

    fileprivate struct State: Sendable {
        /// From ``taskOffset`` on: the oldest finished tasks are let go of on
        /// a long run.
        var tasks: [InspectorTaskRecord] = []
        var taskOffset = 0
        /// By request number, from ``jobOffset`` on.
        var jobs: [InspectorJobRecord] = []
        var jobOffset = 0
        /// The tasks that finished since the model last asked, by index.
        var newlyFinished: [Int] = []
        var imageCount = 0
        var cancelledCount = 0
        var failedCount = 0
        /// The work on each queue: started less ended.
        var running: [InspectorQueue: Int] = [:]
        var waits: [InspectorQueue: InspectorWait] = [:]
        var encodesQueued = 0
        var encodesStarted = 0

        func taskIndex(_ key: InspectorTaskKey) -> Int? {
            let index = key.index - taskOffset
            return tasks.indices.contains(index) ? index : nil
        }

        func jobIndex(_ unit: Int) -> Int? {
            let index = unit - jobOffset
            return jobs.indices.contains(index) ? index : nil
        }

        mutating func updateJob(_ unit: Int, _ body: (inout InspectorJobRecord) -> Void) {
            guard let index = jobIndex(unit) else { return }
            body(&jobs[index])
        }

        /// Records how long the work of a request waited for a queue, from
        /// the moment `since` reads off its record.
        mutating func recordWait(_ queue: InspectorQueue, unit: Int, now: CFTimeInterval, since: (InspectorJobRecord) -> CFTimeInterval?) {
            guard let index = jobIndex(unit), let start = since(jobs[index]) else { return }
            waits[queue, default: InspectorWait()].record(now - start)
        }
    }

    var hasTasks: Bool {
        state.withLock { !$0.tasks.isEmpty || $0.taskOffset > 0 }
    }

    /// The tasks that haven't finished.
    var unsettledCount: Int {
        state.withLock { state in
            state.tasks.count { $0.outcome == nil }
        }
    }

    // MARK: Main Thread

    /// A request of the run, before its tasks are created. Returns its
    /// number.
    func registerRequest(kind: InspectorKind) -> Int {
        state.withLock { state in
            state.jobs.append(InspectorJobRecord(kind: kind))
            return state.jobOffset + state.jobs.count - 1
        }
    }

    /// A task of the request `unit`, right before it is created. Returns the
    /// key its request carries.
    func registerTask(unit: Int, isPartner: Bool, kind: InspectorKind, priority: ImageRequest.Priority) -> InspectorTaskKey {
        let now = CACurrentMediaTime()
        return state.withLock { state in
            let key = InspectorTaskKey(index: state.taskOffset + state.tasks.count, unit: unit, isPartner: isPartner)
            state.tasks.append(InspectorTaskRecord(key: key, kind: kind, createdAt: now, priority: priority))
            return key
        }
    }

    func priorityChanged(_ key: InspectorTaskKey, to priority: ImageRequest.Priority) {
        state.withLock { state in
            guard let index = state.taskIndex(key) else { return }
            state.tasks[index].priority = priority
        }
    }

    /// The indices of the tasks that finished since the last call.
    func takeFinished() -> [Int] {
        state.withLock { state in
            defer { state.newlyFinished = [] }
            return state.newlyFinished
        }
    }

    // MARK: Pipeline

    fileprivate func taskStarted(_ key: InspectorTaskKey) {
        let now = CACurrentMediaTime()
        state.withLock { state in
            guard let index = state.taskIndex(key) else { return }
            state.tasks[index].startedAt = now
            state.updateJob(key.unit) { job in
                job.startedAt = job.startedAt ?? now
            }
        }
    }

    fileprivate func taskFinished(_ key: InspectorTaskKey, _ result: Result<ImageResponse, ImagePipeline.Error>) {
        let now = CACurrentMediaTime()
        let outcome: InspectorTaskRecord.Outcome = switch result {
        case .success: .image
        case .failure(.cancelled): .cancelled
        case .failure(let error): .failed(error.demoCaseName)
        }
        state.withLock { state in
            switch outcome {
            case .image: state.imageCount += 1
            case .cancelled: state.cancelledCount += 1
            case .failed: state.failedCount += 1
            }
            state.newlyFinished.append(key.index)
            guard let index = state.taskIndex(key) else { return }
            state.tasks[index].finishedAt = now
            state.tasks[index].outcome = outcome
        }
    }

    /// A call between the pipeline and the loader, from the probe.
    func record(_ event: DemoPipelineProbe.LoadEvent) {
        guard let key = InspectorTaskKey(event.request) else { return }
        let now = CACurrentMediaTime()
        state.withLock { state in
            switch event.kind {
            case .started:
                state.running[.dataLoading, default: 0] += 1
                state.updateJob(key.unit) { $0.loadStartedAt = now }
                state.recordWait(.dataLoading, unit: key.unit, now: now) { $0.startedAt }
            case let .received(byteCount, response):
                state.updateJob(key.unit) { job in
                    job.receivedByteCount += Int64(byteCount)
                    job.expectedByteCount = max(job.expectedByteCount, response.expectedContentLength)
                }
            case .cancelled:
                break
            case .completed(let error):
                state.running[.dataLoading, default: 0] -= 1
                state.updateJob(key.unit) { job in
                    job.loadEndedAt = now
                    job.isLoadFailed = error != nil
                }
            }
        }
    }

    fileprivate func decodeStarted(_ unit: Int, isAsynchronous: Bool) {
        let now = CACurrentMediaTime()
        state.withLock { state in
            state.updateJob(unit) { $0.decodeStartedAt = now }
            if isAsynchronous {
                state.running[.decoding, default: 0] += 1
                state.recordWait(.decoding, unit: unit, now: now) { $0.loadEndedAt }
            }
        }
    }

    fileprivate func decodeEnded(_ unit: Int, isAsynchronous: Bool) {
        let now = CACurrentMediaTime()
        state.withLock { state in
            if isAsynchronous {
                state.running[.decoding, default: 0] -= 1
            }
            state.updateJob(unit) { $0.decodeEndedAt = now }
        }
    }

    fileprivate func processStarted(_ unit: Int?) {
        let now = CACurrentMediaTime()
        state.withLock { state in
            state.running[.processing, default: 0] += 1
            guard let unit else { return }
            state.updateJob(unit) { $0.processStartedAt = now }
            state.recordWait(.processing, unit: unit, now: now) { $0.decodeEndedAt }
        }
    }

    fileprivate func processEnded() {
        state.withLock { $0.running[.processing, default: 0] -= 1 }
    }

    fileprivate func decompressQueued(_ unit: Int) {
        let now = CACurrentMediaTime()
        state.withLock { $0.updateJob(unit) { $0.decompressQueuedAt = now } }
    }

    fileprivate func decompressStarted(_ unit: Int?) {
        let now = CACurrentMediaTime()
        state.withLock { state in
            state.running[.decompressing, default: 0] += 1
            guard let unit else { return }
            state.updateJob(unit) { $0.decompressStartedAt = now }
            state.recordWait(.decompressing, unit: unit, now: now) { $0.decompressQueuedAt }
        }
    }

    fileprivate func decompressEnded() {
        state.withLock { $0.running[.decompressing, default: 0] -= 1 }
    }

    fileprivate func encodeQueued() {
        state.withLock { $0.encodesQueued += 1 }
    }

    fileprivate func encodeStarted(queuedAt: CFTimeInterval) {
        let now = CACurrentMediaTime()
        state.withLock { state in
            state.encodesStarted += 1
            state.running[.encoding, default: 0] += 1
            state.waits[.encoding, default: .init()].record(now - queuedAt)
        }
    }

    fileprivate func encodeEnded() {
        state.withLock { $0.running[.encoding, default: 0] -= 1 }
    }

    // MARK: Reading

    /// The run now: the counts, the rows, the map, and the queues.
    func sample() -> InspectorSample {
        let start = CACurrentMediaTime()
        var sample = state.withLock { state in
            state.letGoOfOldTasks()
            return state.sample(now: start)
        }
        sample.duration = CACurrentMediaTime() - start
        return sample
    }
}

extension InspectorRecorder.State {
    /// The tasks a long run keeps: past it, the oldest finished tasks, and
    /// the requests behind them, are let go of. Their outcomes stay counted.
    private static let taskLimit = 1_200
    private static let taskLimitAfterTrim = 900

    fileprivate mutating func letGoOfOldTasks() {
        guard tasks.count > Self.taskLimit else { return }
        let removable = tasks.prefix(tasks.count - Self.taskLimitAfterTrim).prefix { $0.outcome != nil }.count
        guard removable > 0 else { return }
        tasks.removeFirst(removable)
        taskOffset += removable
        let firstUnit = tasks.first?.key.unit ?? (jobOffset + jobs.count)
        let removableJobs = min(jobs.count, max(0, firstUnit - jobOffset))
        jobs.removeFirst(removableJobs)
        jobOffset += removableJobs
    }

    fileprivate func sample(now: CFTimeInterval) -> InspectorSample {
        var sample = InspectorSample()
        sample.time = now
        sample.taskCount = taskOffset + tasks.count
        sample.requestCount = jobOffset + jobs.count
        sample.counts[InspectorState.image.rawValue] = imageCount
        sample.counts[InspectorState.cancelled.rawValue] = cancelledCount
        sample.counts[InspectorState.failed.rawValue] = failedCount

        var activeJobs = [Bool](repeating: false, count: jobs.count)
        let firstCell = max(0, tasks.count - InspectorRecorder.cellLimit)
        sample.cells.reserveCapacity(tasks.count - firstCell)
        for (offset, task) in tasks.enumerated() {
            let job = jobIndex(task.key.unit).map { jobs[$0] }
            let state = InspectorState(task: task, job: job)
            if offset >= firstCell {
                sample.cells.append(state)
            }
            guard state.isActive else { continue }
            sample.counts[state.rawValue] += 1
            if let index = jobIndex(task.key.unit) {
                activeJobs[index] = true
            }
            if sample.active.count < InspectorRecorder.activeRowLimit {
                sample.active.append(row(task, job: job, state: state, now: now))
            } else {
                sample.hiddenActiveCount += 1
            }
        }
        for task in tasks.reversed() where task.outcome != nil {
            let job = jobIndex(task.key.unit).map { jobs[$0] }
            sample.finished.append(row(task, job: job, state: InspectorState(task: task, job: job), now: now))
            if sample.finished.count == InspectorRecorder.finishedRowLimit {
                break
            }
        }

        var waiting: [InspectorQueue: Int] = [:]
        for (index, job) in jobs.enumerated() where activeJobs[index] {
            if job.startedAt != nil, job.loadStartedAt == nil {
                waiting[.dataLoading, default: 0] += 1
            }
            if job.kind.decodesOnQueue, job.loadEndedAt != nil, !job.isLoadFailed, job.decodeStartedAt == nil {
                waiting[.decoding, default: 0] += 1
            }
            if job.kind.isProcessed, job.decodeEndedAt != nil, job.processStartedAt == nil {
                waiting[.processing, default: 0] += 1
            }
            if job.decompressQueuedAt != nil, job.decompressStartedAt == nil {
                waiting[.decompressing, default: 0] += 1
            }
        }
        waiting[.encoding] = encodesQueued - encodesStarted
        for queue in InspectorQueue.allCases {
            sample.queues[queue] = InspectorQueueFigures(
                waiting: waiting[queue] ?? 0,
                running: running[queue] ?? 0,
                wait: waits[queue] ?? InspectorWait()
            )
        }
        return sample
    }

    private func row(_ task: InspectorTaskRecord, job: InspectorJobRecord?, state: InspectorState, now: CFTimeInterval) -> InspectorRow {
        var fraction: Double?
        if state == .receiving, let job, job.expectedByteCount > 0 {
            fraction = min(1, Double(job.receivedByteCount) / Double(job.expectedByteCount))
        }
        var failure: String?
        if case .failed(let name)? = task.outcome {
            failure = name
        }
        return InspectorRow(
            key: task.key,
            kind: task.kind,
            priority: task.priority,
            state: state,
            fraction: fraction,
            age: (task.finishedAt ?? now) - task.createdAt,
            failure: failure
        )
    }
}

extension InspectorState {
    /// Where a task is: its own outcome first, then the furthest its
    /// request's work has got.
    init(task: InspectorTaskRecord, job: InspectorJobRecord?) {
        switch task.outcome {
        case .image?:
            self = .image
        case .cancelled?:
            self = .cancelled
        case .failed?:
            self = .failed
        case nil:
            guard task.startedAt != nil else {
                self = .notStarted
                return
            }
            guard let job else {
                self = .queued
                return
            }
            self = Self.stage(of: job)
        }
    }

    private static func stage(of job: InspectorJobRecord) -> InspectorState {
        if job.decompressStartedAt != nil {
            return .decompressing
        }
        if job.decompressQueuedAt != nil {
            return .decompressWaiting
        }
        if job.processStartedAt != nil {
            return .processing
        }
        if job.decodeEndedAt != nil {
            return job.kind.isProcessed ? .processWaiting : .decoding
        }
        if job.decodeStartedAt != nil {
            return .decoding
        }
        if job.loadEndedAt != nil, !job.isLoadFailed {
            return job.kind.decodesOnQueue ? .decodeWaiting : .decoding
        }
        if job.receivedByteCount > 0 {
            return .receiving
        }
        if job.loadStartedAt != nil {
            return .loading
        }
        return .queued
    }
}

// MARK: - Delegate

/// Hears the tasks of a run and the work behind them, through the pipeline's
/// delegate and the decoder, encoder, and processor it hands the pipeline.
///
/// Every hook does what Nuke's own does – it calls it, through an empty
/// delegate – and tells the recorder on the way. The probe forwards to it
/// and counts on top.
final class InspectorDelegate: ImagePipeline.Delegate {
    private let recorder: InspectorRecorder
    private let defaults = DemoDefaultDelegate()

    init(recorder: InspectorRecorder) {
        self.recorder = recorder
    }

    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        guard let decoder = defaults.imageDecoder(for: context, pipeline: pipeline) else {
            return nil
        }
        guard let key = InspectorTaskKey(context.request) else {
            return decoder
        }
        return InspectedDecoder(decoder, unit: key.unit, recorder: recorder)
    }

    /// Asked right before an encode is added to the encoding queue.
    func imageEncoder(for context: ImageEncodingContext, pipeline: ImagePipeline) -> any ImageEncoding {
        recorder.encodeQueued()
        return InspectedEncoder(defaults.imageEncoder(for: context, pipeline: pipeline), recorder: recorder)
    }

    /// Asked right before a decompression is added to the decompressing
    /// queue, and only then.
    func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
        let shouldDecompress = defaults.shouldDecompress(response: response, for: request, pipeline: pipeline)
        if shouldDecompress, let key = InspectorTaskKey(request) {
            recorder.decompressQueued(key.unit)
        }
        return shouldDecompress
    }

    func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse {
        recorder.decompressStarted(InspectorTaskKey(request)?.unit)
        defer { recorder.decompressEnded() }
        return defaults.decompress(response: response, request: request, pipeline: pipeline)
    }

    @ImagePipelineActor
    func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {
        guard let key = InspectorTaskKey(task.request) else { return }
        recorder.taskStarted(key)
    }

    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished(let result) = event, let key = InspectorTaskKey(task.request) else { return }
        recorder.taskFinished(key, result)
    }
}

/// Tells the recorder when a decode starts and ends. Built around a new
/// decoder each time the pipeline asks, as the probe's is:
/// `ImageDecoders.Default` keeps the state of one image.
private final class InspectedDecoder: DemoSynchronousDecoding, CustomStringConvertible {
    private let base: any ImageDecoding
    private let unit: Int
    private let recorder: InspectorRecorder

    init(_ base: any ImageDecoding, unit: Int, recorder: InspectorRecorder) {
        self.base = base
        self.unit = unit
        self.recorder = recorder
    }

    /// Forwarded, so the decode runs where the decoder asked for.
    var isAsynchronous: Bool {
        base.isAsynchronous
    }

    func decode(_ data: Data) throws -> ImageContainer {
        let isAsynchronous = base.isAsynchronous
        recorder.decodeStarted(unit, isAsynchronous: isAsynchronous)
        defer { recorder.decodeEnded(unit, isAsynchronous: isAsynchronous) }
        return try base.decode(data)
    }

    /// Forwarded, uncounted: the runs decode no previews.
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        base.decodePartiallyDownloadedData(data)
    }

    var description: String {
        String(describing: base)
    }
}

/// Tells the recorder when an encode starts and ends. The pipeline creates
/// one right before it adds the encode to the queue, so its creation is when
/// the encode was queued.
private final class InspectedEncoder: ImageEncoding {
    private let base: any ImageEncoding
    private let recorder: InspectorRecorder
    private let queuedAt = CACurrentMediaTime()

    init(_ base: any ImageEncoding, recorder: InspectorRecorder) {
        self.base = base
        self.recorder = recorder
    }

    func encode(_ image: PlatformImage) -> Data? {
        measure { base.encode(image) }
    }

    func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data? {
        measure { base.encode(container, context: context) }
    }

    private func measure(_ encode: () -> Data?) -> Data? {
        recorder.encodeStarted(queuedAt: queuedAt)
        defer { recorder.encodeEnded() }
        return encode()
    }
}

/// The processor of the blurred requests: a resize and a blur, which tells
/// the recorder when it starts and ends. The probe can't see processors,
/// which come with the request.
struct InspectedProcessor: ImageProcessing {
    private let base = ImageProcessors.Composition([
        ImageProcessors.Resize(width: 80),
        ImageProcessors.GaussianBlur(radius: 8)
    ])
    private let recorder: InspectorRecorder

    init(recorder: InspectorRecorder) {
        self.recorder = recorder
    }

    var identifier: String {
        "com.github.kean.NukeDemo.ConcurrencyInspector.blur"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        recorder.processStarted(nil)
        defer { recorder.processEnded() }
        return base.process(image)
    }

    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        recorder.processStarted(InspectorTaskKey(context.request)?.unit)
        defer { recorder.processEnded() }
        return try base.process(container, context: context)
    }
}

/// A disk cache that keeps nothing. With it, the pipeline still encodes what
/// its policy stores, on the encoding queue, and nothing is written, so a
/// run leaves no files and never reads one back.
struct DiscardingDataCache: DataCaching {
    func cachedData(for key: String) -> Data? { nil }
    func containsData(for key: String) -> Bool { false }
    func storeData(_ data: Data, for key: String) {}
    func removeData(for key: String) {}
    func removeAll() {}
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import os

extension DemoPipelineProbe {
    /// One pipeline's figures behind a lock, and the bookkeeping behind them.
    ///
    /// It is an object of its own, rather than state on the probe, because the
    /// decorators hold it. A decorator holding the probe would make a cycle:
    /// the probe keeps the configuration, the configuration keeps its
    /// `DataLoader`, and the loader keeps its session delegate.
    ///
    /// Every method takes the lock once and doesn't allocate on the way, apart
    /// from the dictionaries growing, so it is cheap enough for a chunk of
    /// data or a memory cache lookup.
    final class Counters: Sendable {
        private let state: OSAllocatedUnfairLock<State>

        init(label: String) {
            var figures = DemoPipelineDiagnostics()
            figures.label = label
            state = OSAllocatedUnfairLock(initialState: State(figures: figures))
        }

        /// A copy of the figures.
        var figures: DemoPipelineDiagnostics {
            state.withLock { $0.figures }
        }

        /// Starts the figures over. What is running now stays counted as
        /// running, and is counted when it ends.
        func reset() {
            state.withLock { state in
                let old = state.figures
                var new = DemoPipelineDiagnostics()
                new.label = old.label
                new.activeTaskCount = old.activeTaskCount
                new.cancelledInFlightDownloadCount = old.cancelledInFlightDownloadCount
                new.inFlightByteCount = old.inFlightByteCount
                new.dataLoadingQueue = old.dataLoadingQueue
                new.decodingQueue = old.decodingQueue
                new.decompressingQueue = old.decompressingQueue
                new.encodingQueue = old.encodingQueue
                state.figures = new
            }
        }

        // MARK: Tasks

        func taskCreated(_ task: ImageTask) {
            let id = task.id
            let now = ContinuousClock.now
            state.withLock { state in
                state.taskCreatedAt[id] = now
                state.figures.createdTaskCount += 1
                state.figures.activeTaskCount += 1
            }
        }

        func taskFinished(_ task: ImageTask, with result: Result<ImageResponse, ImagePipeline.Error>) {
            let id = task.id
            let now = ContinuousClock.now
            let outcome = TaskOutcome(result)
            state.withLock { state in
                // A task created before the probe was attached was never counted in.
                guard let createdAt = state.taskCreatedAt.removeValue(forKey: id) else { return }
                state.figures.activeTaskCount -= 1
                switch outcome {
                case .image(let cacheType):
                    state.figures.succeededTaskCount += 1
                    state.figures.taskDuration.record((now - createdAt).demoTimeInterval, at: now)
                    switch cacheType {
                    case .memory?: state.figures.memoryResponseCount += 1
                    case .disk?: state.figures.diskResponseCount += 1
                    case nil: state.figures.networkResponseCount += 1
                    }
                case .cancelled:
                    state.figures.cancelledTaskCount += 1
                case .failed:
                    state.figures.failedTaskCount += 1
                }
            }
        }

        // MARK: Caches

        /// A memory cache hit on the main thread, where NukeUI looks before it
        /// starts a task.
        func memoryHitWithoutTask() {
            state.withLock { $0.figures.memoryHitWithoutTaskCount += 1 }
        }

        func diskCacheLookup(isHit: Bool) {
            state.withLock { state in
                state.figures.diskCacheLookupCount += 1
                if isHit {
                    state.figures.diskCacheHitCount += 1
                }
            }
        }

        func diskWrite(isEncodedImage: Bool) {
            state.withLock { state in
                state.figures.diskWriteCount += 1
                if isEncodedImage {
                    state.figures.encodedImageWriteCount += 1
                }
            }
        }

        // MARK: Downloads

        /// Identifies a load: a `DataLoader`'s session task, or a call to any
        /// other loader.
        enum LoadID: Hashable, Sendable {
            case sessionTask(ObjectIdentifier)
            case call(UInt64)
        }

        enum LoadOutcome: Sendable {
            case completed
            case cancelled
            case failed
        }

        func downloadRequested() {
            state.withLock { $0.figures.downloadCount += 1 }
        }

        /// Starts a load of a loader other than `DataLoader` and returns its id.
        ///
        /// - parameter holdsSlot: `false` for a request with
        ///   `.skipDataLoadingQueue`, which the pipeline loads without a slot.
        func loadStarted(isFixture: Bool, holdsSlot: Bool) -> LoadID {
            let now = ContinuousClock.now
            return state.withLock { state in
                state.nextCallID += 1
                let id = LoadID.call(state.nextCallID)
                state.startLoad(id, at: now, holdsSlot: holdsSlot)
                state.loads[id]?.isFixture = isFixture
                return id
            }
        }

        func loadStarted(_ id: LoadID, holdsSlot: Bool) {
            let now = ContinuousClock.now
            state.withLock { $0.startLoad(id, at: now, holdsSlot: holdsSlot) }
        }

        func load(_ id: LoadID, didReceive byteCount: Int) {
            state.withLock { state in
                guard state.loads[id] != nil else { return }
                state.loads[id]?.byteCount += Int64(byteCount)
                state.figures.inFlightByteCount += Int64(byteCount)
            }
        }

        /// What the session measured, which arrives before the completion.
        func load(_ id: LoadID, isServedFromHTTPCache: Bool) {
            state.withLock { $0.loads[id]?.isServedFromHTTPCache = isServedFromHTTPCache }
        }

        /// The pipeline cancelled a load of a loader other than `DataLoader`.
        func loadCancelled(_ id: LoadID) {
            state.withLock { state in
                guard let load = state.loads[id], !load.isCancelled else { return }
                state.loads[id]?.isCancelled = true
                state.figures.cancelledDownloadCount += 1
                state.figures.cancelledInFlightDownloadCount += 1
            }
        }

        func loadCompleted(_ id: LoadID, outcome: LoadOutcome) {
            state.withLock { state in
                // A loader that calls `completion` twice is counted once.
                guard let load = state.loads.removeValue(forKey: id) else { return }
                if load.holdsSlot {
                    state.figures.dataLoadingQueue.inFlightCount? -= 1
                }
                state.figures.inFlightByteCount -= load.byteCount
                if load.isFixture {
                    if outcome == .completed, !load.isCancelled {
                        state.figures.fixtureLoadCount += 1
                    }
                } else if load.isServedFromHTTPCache {
                    state.figures.httpCacheLoadCount += 1
                } else {
                    state.figures.downloadedByteCount += load.byteCount
                }
                if load.isCancelled {
                    // Counted as cancelled when it was.
                    state.figures.cancelledInFlightDownloadCount -= 1
                    return
                }
                switch outcome {
                case .completed: state.figures.completedDownloadCount += 1
                case .cancelled: state.figures.cancelledDownloadCount += 1
                case .failed: break
                }
            }
        }

        // MARK: Decoding

        func decodeStarted(isAsynchronous: Bool) {
            guard isAsynchronous else { return }
            state.withLock { $0.figures.decodingQueue.inFlightCount? += 1 }
        }

        /// - parameter isFinalImage: whether the decode produced a final
        ///   image, the only kind ``DemoPipelineDiagnostics/decoding`` times.
        func decodeFinished(isAsynchronous: Bool, startedAt: ContinuousClock.Instant, isFinalImage: Bool) {
            let now = ContinuousClock.now
            state.withLock { state in
                if isAsynchronous {
                    state.figures.decodingQueue.inFlightCount? -= 1
                }
                if isFinalImage {
                    state.figures.decoding.record((now - startedAt).demoTimeInterval, at: now)
                }
            }
        }

        /// Counts the decodes a pipeline recording diagnostics measured, from
        /// the record of a finished task.
        ///
        /// A task carries a copy of every job it waited on, so the tasks that
        /// shared a job carry the same stages; each stage is counted the first
        /// time it shows up complete. A stage still running when a task ended
        /// has no duration in that task's copy, and is counted from a later one.
        ///
        /// The record keeps the stages that threw too, with neither a size nor
        /// a format. A stage that produced an image has one of them at least.
        func recordDecodes(from metrics: ImageTask.Metrics) {
            let now = ContinuousClock.now
            state.withLock { state in
                for job in metrics.jobs {
                    for (index, stage) in job.stages.enumerated() where stage.kind == .decode {
                        guard let duration = stage.workDuration,
                              state.countedStages.insert(.init(jobID: job.id, index: index)),
                              stage.isProgressive != true, stage.pixels != nil || stage.format != nil else {
                            continue
                        }
                        state.figures.decoding.record(duration, at: now)
                    }
                }
            }
        }

        // MARK: Decompression

        func decompressionStarted() {
            state.withLock { $0.figures.decompressingQueue.inFlightCount? += 1 }
        }

        func decompressionFinished(startedAt: ContinuousClock.Instant) {
            let now = ContinuousClock.now
            state.withLock { state in
                state.figures.decompressingQueue.inFlightCount? -= 1
                state.figures.decompression.record((now - startedAt).demoTimeInterval, at: now)
            }
        }

        // MARK: Encoding

        func encodeStarted() {
            state.withLock { $0.figures.encodingQueue.inFlightCount? += 1 }
        }

        func encodeFinished(startedAt: ContinuousClock.Instant) {
            let now = ContinuousClock.now
            state.withLock { state in
                state.figures.encodingQueue.inFlightCount? -= 1
                state.figures.encoding.record((now - startedAt).demoTimeInterval, at: now)
            }
        }
    }
}

// MARK: - State

extension DemoPipelineProbe.Counters {
    private struct State: Sendable {
        var figures: DemoPipelineDiagnostics
        /// The tasks created and not yet finished.
        var taskCreatedAt: [ObjectIdentifier: ContinuousClock.Instant] = [:]
        /// The loads started and not yet completed.
        var loads: [LoadID: Load] = [:]
        var nextCallID: UInt64 = 0
        var countedStages = RecentStages()

        mutating func startLoad(_ id: LoadID, at instant: ContinuousClock.Instant, holdsSlot: Bool) {
            guard loads[id] == nil else { return }
            loads[id] = Load(startedAt: instant, holdsSlot: holdsSlot)
            if holdsSlot {
                figures.dataLoadingQueue.inFlightCount? += 1
            }
        }
    }

    private struct Load: Sendable {
        let startedAt: ContinuousClock.Instant
        /// Whether the load holds a data loading slot: counted in the queue's
        /// work in flight.
        let holdsSlot: Bool
        var byteCount: Int64 = 0
        var isCancelled = false
        var isServedFromHTTPCache = false
        /// A load of a ``DemoFixtureLoader``: no network, so none of the
        /// network's figures.
        var isFixture = false
    }

    /// The decode stages already counted from task records: the last thousand,
    /// which is far more than the number of tasks that share a job at once.
    private struct RecentStages: Sendable {
        struct Key: Hashable, Sendable {
            let jobID: UInt64
            let index: Int
        }

        private var keys: Set<Key> = []
        private var order: [Key] = []
        private var oldest = 0
        private let capacity = 1024

        /// Returns `false` if the key is already there.
        mutating func insert(_ key: Key) -> Bool {
            guard !keys.contains(key) else { return false }
            if order.count < capacity {
                order.append(key)
            } else {
                keys.remove(order[oldest])
                order[oldest] = key
                oldest = (oldest + 1) % capacity
            }
            keys.insert(key)
            return true
        }
    }

    private enum TaskOutcome: Sendable {
        case image(ImageResponse.CacheType?)
        case cancelled
        case failed

        init(_ result: Result<ImageResponse, ImagePipeline.Error>) {
            switch result {
            case .success(let response):
                self = .image(response.cacheType)
            case .failure(.cancelled):
                self = .cancelled
            case .failure:
                self = .failed
            }
        }
    }
}

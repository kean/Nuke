// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Recorder

extension ImagePipeline.Diagnostics {
    /// Records the diagnostics of one pipeline.
    ///
    /// The records are written on the pipeline actor, where the task graph
    /// already runs, so they need no locks. The one lock guards the surface
    /// the app reaches from anywhere: the runtime switch and the retention
    /// count.
    ///
    /// Time is read from `ContinuousClock`, which keeps counting through
    /// sleep, and converted to seconds since 1970 only when a record is
    /// captured, using the anchor taken when the recorder was created.
    @ImagePipelineActor
    final class Recorder {
        nonisolated let pipelineID: UUID

        nonisolated private let anchorInstant = ContinuousClock.now
        nonisolated private let anchorTime = Date().timeIntervalSince1970
        nonisolated private let state = OSAllocatedUnfairLock(initialState: State())

        private var nextUnitID: UInt64 = 0
        private var retainedTasks: [ImageTask.Metrics] = []

        private struct State {
            var isEnabled = true
            var retainedTaskCount = 0
        }

        nonisolated init(pipelineID: UUID) {
            self.pipelineID = pipelineID
        }

        // MARK: Surface

        nonisolated var isEnabled: Bool {
            get { state.withLock { $0.isEnabled } }
            set { state.withLock { $0.isEnabled = newValue } }
        }

        nonisolated var retainedTaskCount: Int {
            get { state.withLock { $0.retainedTaskCount } }
            set { state.withLock { $0.retainedTaskCount = newValue } }
        }

        // MARK: Time

        /// Seconds since 1970.
        nonisolated func time(_ instant: ContinuousClock.Instant) -> TimeInterval {
            anchorTime + (instant - anchorInstant).timeInterval
        }

        // MARK: Recording

        /// Starts recording a task, or returns `nil` if the runtime switch is
        /// off. The switch is read here, once per task.
        func makeTaskRecord(for task: ImageTask) -> TaskRecord? {
            guard isEnabled else { return nil }
            return TaskRecord(task: task, recorder: self)
        }

        func makeUnitRecord(kind: Unit.Kind, request: ImageRequest) -> UnitRecord {
            nextUnitID += 1
            return UnitRecord(id: nextUnitID, kind: kind, request: request, recorder: self)
        }

        /// Keeps the last ``retainedTaskCount`` records for the trace.
        func didFinishTask(_ metrics: ImageTask.Metrics) {
            let limit = retainedTaskCount
            guard limit > 0 else {
                if !retainedTasks.isEmpty {
                    retainedTasks.removeAll()
                }
                return
            }
            retainedTasks.append(metrics)
            if retainedTasks.count > limit {
                retainedTasks.removeFirst(retainedTasks.count - limit)
            }
        }

        func makeTrace(pipeline: ImagePipeline) -> Trace {
            Trace(pipeline: pipeline, tasks: retainedTasks)
        }
    }
}

// MARK: - TaskRecord

extension ImagePipeline.Diagnostics {
    /// What one task waited on. Finished into an ``ImageTask/Metrics``
    /// snapshot before the terminal event is dispatched.
    @ImagePipelineActor
    final class TaskRecord {
        let recorder: Recorder
        let taskID: UInt64
        let kind: ImageTask.Metrics.Kind
        let label: String?
        let request: ImageTask.Metrics.RequestSummary
        let createdAt: ContinuousClock.Instant
        private(set) var startedAt: ContinuousClock.Instant?
        private(set) var rootUnit: UnitRecord?
        var previewCount = 0
        private var priorityHistory: [(at: ContinuousClock.Instant, priority: ImageRequest.Priority)] = []

        init(task: ImageTask, recorder: Recorder) {
            self.recorder = recorder
            self.taskID = task.taskId
            self.kind = task._kind
            self.label = task.request.userInfo[.labelKey] as? String
            self.request = ImageTask.Metrics.RequestSummary(task.request)
            self.createdAt = task._createdAt ?? .now
        }

        /// The pipeline started working on the task.
        func didStart() {
            startedAt = .now
        }

        /// The task subscribed to its root unit.
        func didAttach(to unit: UnitRecord) {
            rootUnit = unit
        }

        func recordPriority(_ priority: ImageRequest.Priority) {
            priorityHistory.append((.now, priority))
        }

        /// Captures the record. Called once, when the task finishes.
        func finish(with result: Result<ImageResponse, ImagePipeline.Error>) -> ImageTask.Metrics {
            let now = ContinuousClock.now

            var records: [UnitRecord] = []
            var unit = rootUnit
            while let current = unit {
                records.append(current)
                unit = current.parent
            }
            let units = records.map { $0.makeSnapshot(for: self, at: now) }

            let outcome: Outcome
            var error: ErrorSummary?
            var image: ImageTask.Metrics.ImageSummary?
            switch result {
            case .success(let response):
                outcome = .success
                image = ImageTask.Metrics.ImageSummary(response.container)
            case .failure(let failure):
                outcome = failure.isCancelled ? .cancelled : .failure
                if !failure.isCancelled {
                    error = ErrorSummary(failure)
                }
            }

            let metrics = ImageTask.Metrics(
                schemaVersion: ImagePipeline.Diagnostics.schemaVersion,
                pipelineID: recorder.pipelineID,
                taskID: taskID,
                kind: kind,
                label: label,
                request: request,
                createdAt: recorder.time(createdAt),
                startedAt: startedAt.map(recorder.time),
                endedAt: recorder.time(now),
                duration: (now - createdAt).timeInterval,
                outcome: outcome,
                error: error,
                source: outcome == .success ? Self.source(of: units) : nil,
                isCoalesced: units.contains { $0.joinedAt != nil },
                rootUnitID: rootUnit?.id,
                previewCount: previewCount,
                priorityHistory: priorityHistory.map { PriorityChange(at: recorder.time($0.at), priority: $0.priority) },
                bytes: Self.bytes(of: units),
                image: image,
                units: units
            )
            recorder.didFinishTask(metrics)
            return metrics
        }

        /// The deepest stage that produced the image or its data decides:
        /// a processed image built from an original found on disk came from
        /// the disk.
        private static func source(of units: [Unit]) -> Source? {
            var source: Source?
            for unit in units {
                for stage in unit.stages {
                    switch stage.kind {
                    case .download:
                        source = stage.source ?? source
                    case .diskLookup where stage.result == .hit:
                        source = .disk
                    case .memoryLookup where stage.result == .hit && stage.isProgressive != true:
                        source = .memory
                    default:
                        break
                    }
                }
            }
            return source
        }

        private static func bytes(of units: [Unit]) -> ImageTask.Metrics.Bytes? {
            for unit in units.reversed() {
                for stage in unit.stages where stage.kind == .download {
                    guard let bytes = stage.bytes else { continue }
                    return ImageTask.Metrics.Bytes(downloaded: bytes, resumed: stage.resumedBytes ?? 0, expected: stage.expectedBytes ?? bytes)
                }
            }
            return nil
        }
    }
}

// MARK: - UnitRecord

extension ImagePipeline.Diagnostics {
    /// One piece of shared work, recorded once. Every task that waits on it
    /// gets a copy stamped with the time the task reached it.
    @ImagePipelineActor
    final class UnitRecord {
        let recorder: Recorder
        let id: UInt64
        let kind: Unit.Kind
        let createdAt = ContinuousClock.now
        /// The unit this one subscribed to.
        private(set) var parent: UnitRecord?
        private(set) var createdByTaskID: UInt64?
        private var joins = ContiguousArray<Join>()
        private var peakSubscriberCount = 0
        private(set) var endedAt: ContinuousClock.Instant?
        private var outcome: Outcome?
        private var error: ErrorSummary?
        private var priorityHistory: [PriorityRecord] = []
        private var stages = ContiguousArray<StageRecord>()
        private lazy var processors = request.processors.map(\.identifier)
        private let request: ImageRequest

        private struct Join {
            let taskID: UInt64
            /// `nil` if the task's chain created the unit.
            let joinedAt: ContinuousClock.Instant?
        }

        private struct PriorityRecord {
            let at: ContinuousClock.Instant
            let priority: TaskPriority
        }

        init(id: UInt64, kind: Unit.Kind, request: ImageRequest, recorder: Recorder) {
            self.id = id
            self.kind = kind
            self.request = request
            self.recorder = recorder
            stages.reserveCapacity(4)
        }

        // MARK: Subscribers

        func didSubscribe(_ subscriber: AnyObject, didJoin: Bool, subscriberCount: Int) {
            peakSubscriberCount = max(peakSubscriberCount, subscriberCount)
            (subscriber as? any DiagnosticsSubscriber)?.diagnosticsDidSubscribe(to: self, didJoin: didJoin)
        }

        /// An image task subscribed to the unit.
        func attach(task: TaskRecord, didJoin: Bool) {
            addJoin(task.taskID, at: didJoin ? .now : nil)
            task.didAttach(to: self)
        }

        /// A unit subscribed to the unit, which makes this one its parent.
        func attach(child: UnitRecord, didJoin: Bool) {
            child.parent = self
            if didJoin {
                let now = ContinuousClock.now
                for join in child.joins {
                    addJoin(join.taskID, at: now)
                }
            } else {
                // Created on behalf of the tasks the child already has, who
                // reached it at the same time they reached the child.
                createdByTaskID = child.createdByTaskID
                joins = child.joins
            }
        }

        private func addJoin(_ taskID: UInt64, at joinedAt: ContinuousClock.Instant?) {
            if createdByTaskID == nil {
                createdByTaskID = taskID
            }
            joins.append(Join(taskID: taskID, joinedAt: joinedAt))
            parent?.addJoin(taskID, at: joinedAt ?? .now)
        }

        // MARK: Lifecycle

        func finish(_ outcome: Outcome, error: ImagePipeline.Error? = nil) {
            guard endedAt == nil else { return }
            let now = ContinuousClock.now
            endedAt = now
            self.outcome = outcome
            self.error = error.map(ErrorSummary.init)
            // The work that was running is cancelled along with the unit.
            for index in stages.indices where stages[index].endedAt == nil && stages[index].startedAt != nil {
                stages[index].endedAt = now
            }
        }

        // MARK: Priority

        func recordPriority(_ priority: TaskPriority) {
            guard priorityHistory.last?.priority != priority else { return }
            priorityHistory.append(PriorityRecord(at: .now, priority: priority))
        }

        // MARK: Stages

        /// Appends a stage and returns its index, which is stable: stages are
        /// never removed.
        @discardableResult
        func beginStage(_ kind: Stage.Kind, queued: Bool = false) -> Int {
            let now = ContinuousClock.now
            stages.append(StageRecord(kind: kind, queuedAt: queued ? now : nil, startedAt: queued ? nil : now))
            return stages.count - 1
        }

        /// The queued stage left its queue.
        func startStage(_ index: Int?) {
            guard let index else { return }
            stages[index].startedAt = .now
        }

        func updateStage(_ index: Int?, _ update: (inout StageRecord) -> Void) {
            guard let index else { return }
            update(&stages[index])
        }

        func endStage(_ index: Int?, _ update: (inout StageRecord) -> Void = { _ in }) {
            guard let index else { return }
            update(&stages[index])
            stages[index].endedAt = .now
        }

        /// Records a stage that ran synchronously, from `start` to now.
        func recordStage(_ kind: Stage.Kind, from start: ContinuousClock.Instant, _ update: (inout StageRecord) -> Void = { _ in }) {
            var stage = StageRecord(kind: kind, queuedAt: nil, startedAt: start)
            update(&stage)
            stage.endedAt = .now
            stages.append(stage)
        }

        func endDecodeStage(_ index: Int?, result: Result<ImageResponse, ImagePipeline.Error>, decoder: any ImageDecoding, context: ImageDecodingContext, workDuration: Duration?) {
            endStage(index) {
                $0.decoder = diagnosticsTypeName(of: decoder)
                $0.isProgressive = !context.isCompleted
                $0.workDuration = workDuration
                if case .success(let response) = result {
                    $0.setOutput(response.container)
                }
            }
        }

        // MARK: Snapshot

        /// - parameter task: The task the copy belongs to.
        /// - parameter taskEnd: The end of the task, which the attributed
        /// durations are clamped to.
        func makeSnapshot(for task: TaskRecord, at taskEnd: ContinuousClock.Instant) -> Unit {
            let joinedAt = joins.first { $0.taskID == task.taskID }?.joinedAt
            return Unit(
                id: id,
                kind: kind,
                processors: processors,
                parentID: parent?.id,
                createdByTaskID: createdByTaskID ?? 0,
                taskIDs: joins.map(\.taskID),
                peakSubscriberCount: peakSubscriberCount,
                createdAt: recorder.time(createdAt),
                endedAt: endedAt.map(recorder.time),
                outcome: outcome,
                error: error,
                joinedAt: joinedAt.map(recorder.time),
                priorityHistory: priorityHistory.map {
                    PriorityChange(at: recorder.time($0.at), priority: $0.priority.requestPriority)
                },
                stages: stages.map { $0.makeSnapshot(recorder: recorder, joinedAt: joinedAt, taskEnd: taskEnd) }
            )
        }
    }
}

// MARK: - StageRecord

extension ImagePipeline.Diagnostics {
    /// A stage as it is recorded: instants instead of seconds since 1970, and
    /// the typed fields the recording points fill in.
    struct StageRecord {
        let kind: Stage.Kind
        var queuedAt: ContinuousClock.Instant?
        var startedAt: ContinuousClock.Instant?
        var endedAt: ContinuousClock.Instant?
        var workDuration: Duration?
        var result: Stage.LookupResult?
        var isProgressive: Bool?
        var decoder: String?
        var processor: String?
        var format: String?
        var pixels: PixelSize?
        var frameCount: Int?
        var source: Source?
        var bytes: Int64?
        var resumedBytes: Int64?
        var expectedBytes: Int64?
        var chunkCount: Int?
        var statusCode: Int?
        var firstByteAt: ContinuousClock.Instant?
        var urlSessionTaskID: Int?
        var cost: Int?

        init(kind: Stage.Kind, queuedAt: ContinuousClock.Instant?, startedAt: ContinuousClock.Instant?) {
            self.kind = kind
            self.queuedAt = queuedAt
            self.startedAt = startedAt
        }

        /// Records what a decode, process, or decompress stage produced.
        mutating func setOutput(_ container: ImageContainer) {
            pixels = container.image.diagnosticsPixelSize
            format = container.type?.diagnosticsName
            if let animation = container.animation {
                frameCount = animation.frameCount
            }
        }

        func makeSnapshot(recorder: Recorder, joinedAt: ContinuousClock.Instant?, taskEnd: ContinuousClock.Instant) -> Stage {
            var duration: TimeInterval?
            if let startedAt, let endedAt {
                duration = (endedAt - startedAt).timeInterval
            }
            var attributedDuration: TimeInterval?
            if let startedAt {
                let start = joinedAt.map { max($0, startedAt) } ?? startedAt
                let end = min(endedAt ?? taskEnd, taskEnd)
                attributedDuration = max(0, (end - start).timeInterval)
            }
            return Stage(
                kind: kind,
                queuedAt: queuedAt.map(recorder.time),
                startedAt: startedAt.map(recorder.time),
                duration: duration,
                workDuration: workDuration?.timeInterval,
                attributedDuration: attributedDuration,
                result: result,
                isProgressive: isProgressive,
                decoder: decoder,
                processor: processor,
                format: format,
                pixels: pixels,
                frameCount: frameCount,
                source: source,
                bytes: bytes,
                resumedBytes: resumedBytes,
                expectedBytes: expectedBytes,
                chunkCount: chunkCount,
                statusCode: statusCode,
                firstByteAt: firstByteAt.map(recorder.time),
                urlSessionTaskID: urlSessionTaskID,
                cost: cost
            )
        }
    }
}

// MARK: - Subscribers

/// A subscriber of an `AsyncTask` that the diagnostics attach to the unit:
/// an image task, or a unit acting on behalf of its tasks.
@ImagePipelineActor
protocol DiagnosticsSubscriber: AnyObject {
    func diagnosticsDidSubscribe(to unit: ImagePipeline.Diagnostics.UnitRecord, didJoin: Bool)
}

extension ImageTask: DiagnosticsSubscriber {
    func diagnosticsDidSubscribe(to unit: ImagePipeline.Diagnostics.UnitRecord, didJoin: Bool) {
        guard let record = _diagnostics else { return }
        unit.attach(task: record, didJoin: didJoin)
    }
}

extension AsyncTask: DiagnosticsSubscriber {
    func diagnosticsDidSubscribe(to unit: ImagePipeline.Diagnostics.UnitRecord, didJoin: Bool) {
        guard let diagnostics else { return }
        unit.attach(child: diagnostics, didJoin: didJoin)
    }
}

// MARK: - Summaries

extension ImageTask.Metrics.RequestSummary {
    init(_ request: ImageRequest) {
        self.url = request.url?.absoluteString
        self.imageID = request.imageID
        self.processors = request.processors.map(\.identifier)
        self.thumbnail = request.thumbnail?.identifier
        self.options = request.options.diagnosticsNames
        self.priority = request.priority
    }
}

extension ImageTask.Metrics.ImageSummary {
    init(_ container: ImageContainer) {
        let pixels = container.image.diagnosticsPixelSize
        self.width = pixels?.width ?? 0
        self.height = pixels?.height ?? 0
        self.format = container.type?.diagnosticsName
        self.isAnimated = container.animation != nil
    }
}

extension ImagePipeline.Diagnostics.ErrorSummary {
    init(_ error: ImagePipeline.Error) {
        let code: String
        var underlying: (any Swift.Error)?
        switch error {
        case .dataMissingInCache: code = "dataMissingInCache"
        case .dataLoadingFailed(let error):
            code = "dataLoadingFailed"
            underlying = error
        case .dataIsEmpty: code = "dataIsEmpty"
        case .decoderNotRegistered: code = "decoderNotRegistered"
        case .decodingFailed(_, _, let error):
            code = "decodingFailed"
            underlying = error
        case .processingFailed(_, _, let error):
            code = "processingFailed"
            underlying = error
        case .imageRequestMissing: code = "imageRequestMissing"
        case .pipelineInvalidated: code = "pipelineInvalidated"
        case .dataDownloadExceededMaximumSize: code = "dataDownloadExceededMaximumSize"
        case .cancelled: code = "cancelled"
        }
        let nsError = underlying.map { $0 as NSError }
        self.init(code: code, description: error.description, underlyingDomain: nsError?.domain, underlyingCode: nsError?.code)
    }
}

extension ImageRequest.Options {
    private static let diagnosticsNames: [(ImageRequest.Options, String)] = [
        (.disableMemoryCacheReads, "disableMemoryCacheReads"),
        (.disableMemoryCacheWrites, "disableMemoryCacheWrites"),
        (.disableDiskCacheReads, "disableDiskCacheReads"),
        (.disableDiskCacheWrites, "disableDiskCacheWrites"),
        (.returnCacheDataDontLoad, "returnCacheDataDontLoad"),
        (.skipDecompression, "skipDecompression"),
        (.skipDataLoadingQueue, "skipDataLoadingQueue")
    ]

    var diagnosticsNames: [String] {
        guard !isEmpty else { return [] }
        return Self.diagnosticsNames.filter { contains($0.0) }.map(\.1)
    }
}

extension AssetType {
    /// A short name for the records, such as `"jpeg"`.
    var diagnosticsName: String {
        switch self {
        case .jpeg: "jpeg"
        case .png: "png"
        case .gif: "gif"
        case .heic: "heic"
        case .webp: "webp"
        case .avif: "avif"
        case .bmp: "bmp"
        case .tiff: "tiff"
        case .ico: "ico"
        case .jpeg2000: "jpeg2000"
        case .jxl: "jxl"
        case .mp4: "mp4"
        case .m4v: "m4v"
        case .mov: "mov"
        default: rawValue
        }
    }
}

extension PlatformImage {
    /// The size of the bitmap, measured the way ``ImageCache`` measures its cost.
    var diagnosticsPixelSize: ImagePipeline.Diagnostics.PixelSize? {
        guard let cgImage else { return nil }
        return .init(width: cgImage.width, height: cgImage.height)
    }
}

extension TaskPriority {
    var requestPriority: ImageRequest.Priority {
        switch self {
        case .veryLow: .veryLow
        case .low: .low
        case .normal: .normal
        case .high: .high
        case .veryHigh: .veryHigh
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

/// The name of the type of the value without its module, such as
/// `"ImageDecoders.Default"`.
func diagnosticsTypeName(of value: Any) -> String {
    let name = String(reflecting: type(of: value))
    guard let dot = name.firstIndex(of: "."), !name.hasPrefix("(") else {
        return name
    }
    return String(name[name.index(after: dot)...])
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

// MARK: - Recorder

extension ImagePipeline.Diagnostics {
    /// Records the diagnostics of one pipeline.
    ///
    /// The records are written on the pipeline actor, where the task graph
    /// already runs, so they need no locks. The one lock guards the surface
    /// the app reaches from anywhere: the runtime switch.
    ///
    /// Time is read from `ContinuousClock`, which keeps counting through
    /// sleep, and converted to seconds since 1970 only when a record is
    /// captured, using the anchor taken when the recorder was created.
    @ImagePipelineActor
    final class Recorder {
        nonisolated let pipelineID: UUID

        nonisolated private let anchorInstant = ContinuousClock.now
        nonisolated private let anchorTime = Date().timeIntervalSince1970
        nonisolated private let _isEnabled = OSAllocatedUnfairLock(initialState: true)

        private var nextJobID: UInt64 = 0

        nonisolated init(pipelineID: UUID) {
            self.pipelineID = pipelineID
        }

        /// The runtime switch, which the app reaches from any thread.
        nonisolated var isEnabled: Bool {
            get { _isEnabled.withLock { $0 } }
            set { _isEnabled.withLock { $0 = newValue } }
        }

        /// Seconds since 1970.
        nonisolated func time(_ instant: ContinuousClock.Instant) -> TimeInterval {
            anchorTime + (instant - anchorInstant).timeInterval
        }

        nonisolated func priorityChanges(_ history: [PriorityRecord]) -> [PriorityChange] {
            history.map { PriorityChange(at: time($0.at), priority: $0.priority) }
        }

        /// Starts recording a task, or returns `nil` if the runtime switch is
        /// off. The switch is read here, once per task.
        func makeTaskRecord(for task: ImageTask) -> TaskRecord? {
            guard isEnabled else { return nil }
            return TaskRecord(task: task, recorder: self)
        }

        func makeJobRecord(kind: Job.Kind, request: ImageRequest) -> JobRecord {
            nextJobID += 1
            return JobRecord(id: nextJobID, kind: kind, request: request, recorder: self)
        }
    }

    /// A priority change as it is recorded, before the instant becomes
    /// seconds since 1970.
    struct PriorityRecord {
        let at: ContinuousClock.Instant
        let priority: ImageRequest.Priority
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
        private(set) var rootJob: JobRecord?
        var previewCount = 0
        private var priorityHistory: [PriorityRecord] = []

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

        /// The task subscribed to its root job.
        func didAttach(to job: JobRecord) {
            rootJob = job
        }

        func recordPriority(_ priority: ImageRequest.Priority) {
            priorityHistory.append(PriorityRecord(at: .now, priority: priority))
        }

        /// Captures the record. Called once, when the task finishes.
        func finish(with result: Result<ImageResponse, ImagePipeline.Error>) -> ImageTask.Metrics {
            let now = ContinuousClock.now

            var jobs: [Job] = []
            var job = rootJob
            while let current = job {
                jobs.append(current.makeSnapshot(for: self, at: now))
                job = current.parent
            }

            let outcome: Outcome
            var error: ErrorSummary?
            var image: ImageTask.Metrics.ImageSummary?
            switch result {
            case .success(let response):
                outcome = .success
                image = ImageTask.Metrics.ImageSummary(response.container)
            case .failure(let failure) where failure.isCancelled:
                outcome = .cancelled
            case .failure(let failure):
                outcome = .failure
                error = ErrorSummary(failure)
            }

            return ImageTask.Metrics(
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
                source: outcome == .success ? Self.source(of: jobs) : nil,
                isCoalesced: jobs.contains { $0.joinedAt != nil },
                rootJobID: rootJob?.id,
                previewCount: previewCount,
                priorityHistory: recorder.priorityChanges(priorityHistory),
                bytes: Self.bytes(of: jobs),
                image: image,
                jobs: jobs
            )
        }

        /// The deepest stage that produced the image or its data decides:
        /// a processed image built from an original found on disk came from
        /// the disk.
        private static func source(of jobs: [Job]) -> Source? {
            var source: Source?
            for job in jobs {
                for stage in job.stages {
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

        private static func bytes(of jobs: [Job]) -> ImageTask.Metrics.Bytes? {
            for job in jobs.reversed() {
                for stage in job.stages where stage.kind == .download {
                    guard let bytes = stage.bytes else { continue }
                    return ImageTask.Metrics.Bytes(downloaded: bytes, resumed: stage.resumedBytes ?? 0, expected: stage.expectedBytes ?? bytes)
                }
            }
            return nil
        }
    }
}

// MARK: - JobRecord

extension ImagePipeline.Diagnostics {
    /// One piece of shared work, recorded once. Every task that waits on it
    /// gets a copy stamped with the time the task reached it.
    @ImagePipelineActor
    final class JobRecord {
        let recorder: Recorder
        let id: UInt64
        let kind: Job.Kind
        let createdAt = ContinuousClock.now
        /// The job this one subscribed to.
        private(set) var parent: JobRecord?
        private(set) var createdByTaskID: UInt64?
        private var joins: [Join] = []
        private(set) var endedAt: ContinuousClock.Instant?
        private var outcome: Outcome?
        private var error: ErrorSummary?
        private var priorityHistory: [PriorityRecord] = []
        private var stages: [StageRecord] = []
        /// The identifiers of the processors the job applies.
        private let processors: [String]

        private struct Join {
            let taskID: UInt64
            /// `nil` if the task's chain created the job.
            let joinedAt: ContinuousClock.Instant?
        }

        init(id: UInt64, kind: Job.Kind, request: ImageRequest, recorder: Recorder) {
            self.id = id
            self.kind = kind
            self.processors = request.processors.map(\.identifier)
            self.recorder = recorder
        }

        // MARK: Subscribers

        func didSubscribe(_ subscriber: AnyObject, didJoin: Bool) {
            (subscriber as? any DiagnosticsSubscriber)?.diagnosticsDidSubscribe(to: self, didJoin: didJoin)
        }

        /// An image task subscribed to the job.
        func attach(task: TaskRecord, didJoin: Bool) {
            addJoin(task.taskID, at: didJoin ? .now : nil)
            task.didAttach(to: self)
        }

        /// Another job subscribed to this one, which makes this one its parent.
        func attach(child: JobRecord, didJoin: Bool) {
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
            // The work that was running is cancelled along with the job.
            for index in stages.indices where stages[index].endedAt == nil && stages[index].startedAt != nil {
                stages[index].endedAt = now
            }
        }

        func recordPriority(_ priority: TaskPriority) {
            let priority = priority.requestPriority
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
            var stage = StageRecord(kind: kind, startedAt: start)
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
        func makeSnapshot(for task: TaskRecord, at taskEnd: ContinuousClock.Instant) -> Job {
            let joinedAt = joins.first { $0.taskID == task.taskID }?.joinedAt
            return Job(
                id: id,
                kind: kind,
                processors: processors,
                parentID: parent?.id,
                createdByTaskID: createdByTaskID ?? 0,
                taskIDs: joins.map(\.taskID),
                createdAt: recorder.time(createdAt),
                endedAt: endedAt.map(recorder.time),
                outcome: outcome,
                error: error,
                joinedAt: joinedAt.map(recorder.time),
                priorityHistory: recorder.priorityChanges(priorityHistory),
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
        var source: Source?
        var bytes: Int64?
        var resumedBytes: Int64?
        var expectedBytes: Int64?
        var statusCode: Int?
        var firstByteAt: ContinuousClock.Instant?
        var urlSessionTaskID: Int?
        /// What `URLSession` measured for a download, once it completed.
        var urlSessionMetrics: URLSessionMetrics?

        /// Records what a decode, process, or decompress stage produced.
        mutating func setOutput(_ container: ImageContainer) {
            pixels = container.image.diagnosticsPixelSize
            format = container.type?.diagnosticsName
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
                source: source,
                bytes: bytes,
                resumedBytes: resumedBytes,
                expectedBytes: expectedBytes,
                statusCode: statusCode,
                firstByteAt: firstByteAt.map(recorder.time),
                urlSessionTaskID: urlSessionTaskID,
                urlSessionMetrics: urlSessionMetrics
            )
        }
    }
}

// MARK: - Subscribers

/// A subscriber of an `AsyncTask` that the diagnostics attach to the job:
/// an image task, or a job acting on behalf of its tasks.
@ImagePipelineActor
protocol DiagnosticsSubscriber: AnyObject {
    func diagnosticsDidSubscribe(to job: ImagePipeline.Diagnostics.JobRecord, didJoin: Bool)
}

extension ImageTask: DiagnosticsSubscriber {
    func diagnosticsDidSubscribe(to job: ImagePipeline.Diagnostics.JobRecord, didJoin: Bool) {
        guard let record = _diagnostics else { return }
        job.attach(task: record, didJoin: didJoin)
    }
}

extension AsyncTask: DiagnosticsSubscriber {
    func diagnosticsDidSubscribe(to job: ImagePipeline.Diagnostics.JobRecord, didJoin: Bool) {
        guard let diagnostics else { return }
        job.attach(child: diagnostics, didJoin: didJoin)
    }
}

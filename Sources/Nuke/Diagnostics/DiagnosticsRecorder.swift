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
    /// sleep, and written as seconds since 1970 against the anchor taken
    /// when the recorder was created.
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

        /// Now, in seconds since 1970.
        nonisolated var now: TimeInterval { time(.now) }

        /// Seconds since 1970.
        nonisolated func time(_ instant: ContinuousClock.Instant) -> TimeInterval {
            anchorTime + (instant - anchorInstant).timeInterval
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
        /// Seconds since 1970.
        let createdAt: TimeInterval
        private(set) var startedAt: TimeInterval?
        private(set) var rootJob: JobRecord?
        var previewCount = 0
        private var priorityHistory: [PriorityChange] = []

        init(task: ImageTask, recorder: Recorder) {
            self.recorder = recorder
            self.taskID = task.taskId
            self.kind = task._kind
            self.label = task.request.userInfo[.labelKey] as? String
            self.request = ImageTask.Metrics.RequestSummary(task.request)
            self.createdAt = task._createdAt ?? recorder.now
        }

        /// The pipeline started working on the task, at the given time.
        /// Taking the time instead of reading the clock here keeps the cost
        /// of building this record out of the wait that the record reports.
        func didStart(at time: TimeInterval) {
            startedAt = time
        }

        /// The task subscribed to its root job.
        func didAttach(to job: JobRecord) {
            rootJob = job
        }

        func recordPriority(_ priority: ImageRequest.Priority) {
            priorityHistory.append(PriorityChange(at: recorder.now, priority: priority))
        }

        /// Captures the record. Called once, when the task finishes.
        func finish(with result: Result<ImageResponse, ImagePipeline.Error>) -> ImageTask.Metrics {
            let now = recorder.now

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
                createdAt: createdAt,
                startedAt: startedAt,
                endedAt: now,
                duration: now - createdAt,
                outcome: outcome,
                error: error,
                source: outcome == .success ? Self.source(of: jobs) : nil,
                isCoalesced: jobs.contains { $0.joinedAt != nil },
                rootJobID: rootJob?.id,
                previewCount: previewCount,
                priorityHistory: priorityHistory,
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
    /// One piece of shared work, recorded once into the ``Job`` it becomes.
    /// Every task that waits on it captures a copy, stamped with what is true
    /// for that task.
    @ImagePipelineActor
    final class JobRecord {
        let recorder: Recorder
        /// The job as it is recorded. The fields a task decides – the time it
        /// joined, and what it waited for – are stamped on its copy.
        private var job: Job
        /// The job this one subscribed to.
        private(set) var parent: JobRecord?
        /// Every task that reached the job, in the order they did. The first
        /// one created it.
        private var joins: [Join] = []

        /// Publishes the stages to the Instruments app, and `nil` when
        /// nothing was collecting them as the job started.
        private let signposter: Signposter?

        var id: UInt64 { job.id }

        private struct Join {
            let taskID: UInt64
            /// `nil` if the task's chain created the job.
            let joinedAt: TimeInterval?
        }

        init(id: UInt64, kind: Job.Kind, request: ImageRequest, recorder: Recorder) {
            self.recorder = recorder
            self.signposter = Signposter(request: request)
            self.job = Job(
                id: id,
                kind: kind,
                processors: request.processors.map(\.identifier),
                createdByTaskID: 0,
                createdAt: recorder.now
            )
        }

        // MARK: Subscribers

        func didSubscribe(_ subscriber: AnyObject, didJoin: Bool) {
            (subscriber as? any DiagnosticsSubscriber)?.diagnosticsDidSubscribe(to: self, didJoin: didJoin)
        }

        /// An image task subscribed to the job.
        func attach(task: TaskRecord, didJoin: Bool) {
            addJoin(task.taskID, at: didJoin ? recorder.now : nil)
            task.didAttach(to: self)
        }

        /// Another job subscribed to this one, which makes this one its parent.
        func attach(child: JobRecord, didJoin: Bool) {
            child.parent = self
            child.job.parentID = job.id
            if didJoin {
                let now = recorder.now
                for join in child.joins {
                    addJoin(join.taskID, at: now)
                }
            } else {
                // Created on behalf of the tasks the child already has, who
                // reached it at the same time they reached the child.
                joins = child.joins
            }
        }

        private func addJoin(_ taskID: UInt64, at joinedAt: TimeInterval?) {
            joins.append(Join(taskID: taskID, joinedAt: joinedAt))
            parent?.addJoin(taskID, at: joinedAt ?? recorder.now)
        }

        // MARK: Lifecycle

        func finish(_ outcome: Outcome, error: ImagePipeline.Error? = nil) {
            guard job.endedAt == nil else { return }
            let now = recorder.now
            job.endedAt = now
            job.outcome = outcome
            job.error = error.map(ErrorSummary.init)
            // The work that was running is cancelled along with the job.
            for index in job.stages.indices where job.stages[index].isRunning {
                job.stages[index].end(at: now)
                signposter?.end(job.stages[index], outcome.rawValue)
            }
        }

        func recordPriority(_ priority: TaskPriority) {
            let priority = priority.requestPriority
            guard job.priorityHistory.last?.priority != priority else { return }
            job.priorityHistory.append(PriorityChange(at: recorder.now, priority: priority))
        }

        // MARK: Stages

        /// Appends a stage and returns its index, which is stable: stages are
        /// never removed.
        ///
        /// - parameter isProgressive: Whether the stage works on a preview,
        /// for the work that knows it upfront. The signpost interval is named
        /// after it, so it can't wait until the stage ends.
        @discardableResult
        func beginStage(_ kind: Stage.Kind, queued: Bool = false, isProgressive: Bool? = nil) -> Int {
            let now = recorder.now
            var stage = Stage(kind: kind, queuedAt: queued ? now : nil, startedAt: queued ? nil : now)
            stage.isProgressive = isProgressive
            job.stages.append(stage)
            let index = job.stages.count - 1
            if !queued {
                signposter?.begin(stage)
            }
            return index
        }

        /// The queued stage left its queue.
        func startStage(_ index: Int?) {
            guard let index else { return }
            job.stages[index].startedAt = recorder.now
            signposter?.begin(job.stages[index])
        }

        func updateStage(_ index: Int?, _ update: (inout Stage) -> Void) {
            guard let index else { return }
            update(&job.stages[index])
        }

        func endStage(_ index: Int?, _ update: (inout Stage) -> Void = { _ in }) {
            guard let index else { return }
            update(&job.stages[index])
            guard job.stages[index].isRunning else { return } // The job ended it
            job.stages[index].end(at: recorder.now)
            signposter?.end(job.stages[index])
        }

        /// Records a stage that ran synchronously, from `start` to now. It is
        /// already over by the time it's recorded, so it opens no interval.
        func recordStage(_ kind: Stage.Kind, from start: ContinuousClock.Instant, _ update: (inout Stage) -> Void = { _ in }) {
            var stage = Stage(kind: kind, queuedAt: nil, startedAt: recorder.time(start))
            update(&stage)
            stage.end(at: recorder.now)
            job.stages.append(stage)
        }

        /// The first chunk of a download arrived.
        func recordFirstByte(_ index: Int?, statusCode: Int?) {
            let now = recorder.now
            updateStage(index) {
                guard $0.firstByteAt == nil else { return }
                $0.firstByteAt = now
                $0.statusCode = statusCode
            }
        }

        func endDecodeStage(_ index: Int?, result: Result<ImageResponse, ImagePipeline.Error>, decoder: any ImageDecoding, workDuration: TimeInterval?) {
            endStage(index) {
                $0.decoder = diagnosticsTypeName(of: decoder)
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
        func makeSnapshot(for task: TaskRecord, at taskEnd: TimeInterval) -> Job {
            var copy = job
            copy.createdByTaskID = joins.first?.taskID ?? 0
            copy.taskIDs = joins.map(\.taskID)
            copy.joinedAt = joins.first { $0.taskID == task.taskID }?.joinedAt
            copy.stages = job.stages.map { $0.attributed(joinedAt: copy.joinedAt, taskEnd: taskEnd) }
            return copy
        }
    }
}

// MARK: - Stage

extension ImagePipeline.Diagnostics.Stage {
    /// Records what a decode, process, or decompress stage produced.
    mutating func setOutput(_ container: ImageContainer) {
        pixels = container.image.diagnosticsPixelSize
        format = container.type?.diagnosticsName
    }

    /// `true` between the moment the work starts and the moment it ends. A
    /// stage that never left its queue never runs, and has nothing to measure.
    var isRunning: Bool { startedAt != nil && duration == nil }

    /// Closes the stage, if it is running.
    mutating func end(at now: TimeInterval) {
        guard let startedAt, duration == nil else { return }
        duration = max(0, now - startedAt)
    }

    /// The copy one task carries: the same stage with the share of its
    /// duration the task waited for. The work that ran before the task
    /// joined, or after the task ended, is not the task's to pay for.
    func attributed(joinedAt: TimeInterval?, taskEnd: TimeInterval) -> Self {
        guard let startedAt else { return self }
        let duration = duration ?? max(0, taskEnd - startedAt)
        let joinWait = max(0, (joinedAt ?? startedAt) - startedAt)
        let overrun = max(0, (startedAt + duration) - taskEnd)
        var copy = self
        copy.attributedDuration = max(0, duration - joinWait - overrun)
        return copy
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

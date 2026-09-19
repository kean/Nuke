// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: a stage that was queued but never left its queue is reported
// as the work of its kind – a `download` that never ran is `network` time –
// instead of as a wait for the queue.
//
// Where: Sources/Nuke/Diagnostics/ImageTask+Metrics.swift:280 (`timeShares`)
// and Sources/Nuke/Diagnostics/ImageTask+MetricsFormat.swift:434 (`split`).
// Both only carve out the queue wait when `stage.startedAt` is set:
//
//     if stage.queuedAt != nil, let startedAt = stage.startedAt, startedAt > span.from {
//         ... queue ...
//     } else {
//         intervals.append((category(of: stage.kind), span))   // <- never-started stage lands here
//     }
//
// A never-started stage's span runs from `queuedAt` to the end of the task, so
// the whole wait is charged to `category(of: .download) == .network`, the row
// is drawn as a solid bar, and no `dataLoadingQueue` wait row is printed.
//
// Expected (docs): `Category.queue` is "The wait for one of the queues in
// ImagePipeline.Configuration, which is where the time goes when the pipeline
// is busy"; `Options.chart` draws "Light for a wait"; the timeline gives "a
// stage that waited a millisecond, or a tenth of the task, for its queue ... a
// row for the wait, named after the queue". A task cancelled while its
// download waited 30 ms for `dataLoadingQueue` should read `queue 30 ms`.
//
// Actual: `time: network 30.4 ms (100%) · other <0.1 ms`, and
// `└─ download  30.4 ms  ████████████████████  100%  never started`.
//
// This is the common case the breakdown exists for: a list scrolled past its
// cells cancels the tasks that are still waiting for a busy data loading
// queue, and every one of them reports its wait as network time.
//
// It reaches successful tasks too. With progressive decoding and a processor,
// the preview's `process` is enqueued, and cancelled while still queued when
// the final image arrives (`TaskLoadImage.process`: `operation?.cancel()`).
// Its stage never starts, so its span runs from its `queuedAt` to the end of
// the task and is charged as `process` – over the decode, the cache writes and
// the hops that followed. A task whose only process ran 2.4 ms reports
// `process 3.0 ms`, and its timeline carries a solid `process … never started`
// bar next to the real one.
//
// It reaches successful tasks too. With progressive decoding and a processor,
// the preview's `process` is enqueued, and cancelled while still queued when
// the final image arrives (`TaskLoadImage.process`: `operation?.cancel()`).
// Its stage never starts, so its span runs from its `queuedAt` to the end of
// the task and is charged as `process` – over the decode, the cache writes and
// the hops that followed. A task whose only process ran 2.4 ms reports
// `process 3.0 ms`, and its timeline carries a solid `process … never started`
// bar next to the real one.
@Suite(.timeLimit(.minutes(5)))
struct DiagnosticsNeverStartedStageRepro {
    /// A task cancelled while its download waits for `dataLoadingQueue`.
    @Test @ImagePipelineActor func downloadThatNeverLeftItsQueueIsNotNetworkTime() async throws {
        // GIVEN a data loading queue that holds its work
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
            $0.dataCache = nil
            $0.isDiagnosticsEnabled = true
        }
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        defer { queue.isSuspended = false }
        var task: ImageTask?
        _ = await queue.waitForOperations(count: 1) {
            task = pipeline.imageTask(with: Test.request)
        }
        let imageTask = try #require(task)

        // WHEN it is cancelled while it waits
        imageTask.cancel()
        _ = try? await imageTask.response

        // THEN (precondition) the download never started
        let metrics = try #require(imageTask.metrics)
        let download = try #require(metrics.jobs.last?.stages.first { $0.kind == .download })
        try #require(download.queuedAt != nil && download.startedAt == nil)

        // THEN the wait is queue time, not network time
        let categories = metrics.timeShares.map(\.category)
        #expect(!categories.contains(.network), "A download that never ran is reported as network time: \(metrics.timeShares.map { "\($0.category) \($0.duration)" })\n\(metrics.description)")
        #expect(categories.contains(.queue), "The wait for the queue is missing: \(metrics.timeShares.map { "\($0.category) \($0.duration)" })")
    }

    /// A successful progressive task: the preview's `process` never left the
    /// queue, and it isn't process time.
    @Test @ImagePipelineActor func previewProcessThatNeverRanIsNotProcessTime() async throws {
        // GIVEN a processing queue that holds its work, and a download that
        // serves the first scan before the rest
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.isDiagnosticsEnabled = true
        }
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true
        defer { queue.isSuspended = false }
        var task: ImageTask?
        // The preview's process is enqueued...
        _ = await queue.waitForOperations(count: 1) {
            task = pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [.resize(width: 100)]))
        }
        // ...and replaced by the final one while it waits
        _ = await queue.waitForOperations(count: 1) {
            dataLoader.resumeServingChunks(2)
        }
        queue.isSuspended = false
        let imageTask = try #require(task)
        _ = try await imageTask.response

        // THEN (precondition) one process never ran, the other did
        let metrics = try #require(imageTask.metrics)
        let processes = metrics.jobs[0].stages.filter { $0.kind == .process }
        try #require(processes.count == 2)
        try #require(processes.filter { $0.startedAt == nil }.count == 1)
        let ran = try #require(processes.first { $0.startedAt != nil }?.duration)

        // THEN the task spent no more time processing than the process took
        let process = try #require(metrics.timeShares.first { $0.category == .process }).duration
        #expect(process <= ran + 1e-6, "process \(process * 1000) ms in the breakdown, \(ran * 1000) ms of processing:\n\(metrics.description)")
    }

    /// A successful progressive task: the preview's `process` never left the
    /// queue, and it isn't process time.
    @Test @ImagePipelineActor func previewProcessThatNeverRanIsNotProcessTime() async throws {
        // GIVEN a processing queue that holds its work, and a download that
        // serves the first scan before the rest
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.isDiagnosticsEnabled = true
        }
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true
        defer { queue.isSuspended = false }
        var task: ImageTask?
        // The preview's process is enqueued...
        _ = await queue.waitForOperations(count: 1) {
            task = pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [.resize(width: 100)]))
        }
        // ...and replaced by the final one while it waits
        _ = await queue.waitForOperations(count: 1) {
            dataLoader.resumeServingChunks(2)
        }
        queue.isSuspended = false
        let imageTask = try #require(task)
        _ = try await imageTask.response

        // THEN (precondition) one process never ran, the other did
        let metrics = try #require(imageTask.metrics)
        let processes = metrics.jobs[0].stages.filter { $0.kind == .process }
        try #require(processes.count == 2)
        try #require(processes.filter { $0.startedAt == nil }.count == 1)
        let ran = try #require(processes.first { $0.startedAt != nil }?.duration)

        // THEN the task spent no more time processing than the process took
        let process = try #require(metrics.timeShares.first { $0.category == .process }).duration
        #expect(process <= ran + 1e-6, "process \(process * 1000) ms in the breakdown, \(ran * 1000) ms of processing:\n\(metrics.description)")
    }

    /// The same shape on a record built by hand, so the numbers are exact: a
    /// 1 s task whose download was enqueued at the start and never started.
    @Test func neverStartedStageIsAWaitInTheBreakdownAndTheChart() throws {
        // GIVEN
        let t0: TimeInterval = 1_000_000
        let stage = ImagePipeline.Diagnostics.Stage(kind: .download, queuedAt: t0, startedAt: nil)
        let job = ImagePipeline.Diagnostics.Job(id: 1, kind: .fetchOriginalData, processors: [], createdByTaskID: 1, taskIDs: [1], createdAt: t0, endedAt: t0 + 1, outcome: .cancelled, stages: [stage])
        let metrics = ImageTask.Metrics(
            schemaVersion: 2, pipelineID: UUID(), taskID: 1, kind: .image, label: nil,
            request: .init(url: "https://example.com/a.jpeg", imageID: "https://example.com/a.jpeg", processors: [], thumbnail: nil, options: [], priority: .normal),
            createdAt: t0, startedAt: t0, endedAt: t0 + 1, duration: 1, outcome: .cancelled, error: nil, source: nil,
            isCoalesced: false, rootJobID: 1, previewCount: 0, priorityHistory: [], bytes: nil, image: nil, jobs: [job]
        )

        // THEN the whole second is the wait for the queue
        let shares = metrics.timeShares
        #expect(shares.map(\.category) == [.queue], "Unexpected shares: \(shares.map { "\($0.category) \($0.duration)" })")

        // THEN the wait is drawn light and named after the queue
        let description = metrics.formatted([.timeline, .chart])
        let row = try #require(description.split(separator: "\n").first { $0.contains("─ download ") })
        #expect(!row.contains("█"), "Work drawn for a stage that never ran:\n\(description)")
        #expect(description.contains("─ dataLoadingQueue "), "No wait row for the queue:\n\(description)")
    }
}

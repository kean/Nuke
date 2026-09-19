// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: the time `ImagePipeline.Delegate.willLoadData` takes is
// reported as a wait for `dataLoadingQueue`, on an idle pipeline whose queue
// admitted the download at once – and even with `.skipDataLoadingQueue`, where
// there is no queue at all. The `willLoadData` stage maps to `other`, which
// ranks last, and the download's queue interval (`queuedAt` → `startedAt`)
// covers the whole delegate call, so the delegate's time always lands in
// `queue`: the `.willLoadData → .other` mapping can never take effect.
//
// Where: Sources/Nuke/Tasks/TaskFetchOriginalData.swift:72 and :118-130 –
// `downloadStage` is begun (queued) in `loadData(urlRequest:)`, the queue (or
// the `Task` of `.skipDataLoadingQueue`) runs `performDataLoad`, which awaits
// the delegate, and only then calls `diagnostics?.startStage(downloadStage)`.
// `timeShares` (Sources/Nuke/Diagnostics/ImageTask+Metrics.swift:280-284)
// then charges `queuedAt..startedAt` to `.queue` (rank 1), which beats the
// overlapping `.willLoadData` stage (`.other`, rank 7).
//
// Expected (docs): `Category.queue` is "The wait for one of the queues in
// ImagePipeline.Configuration, which is where the time goes when the pipeline
// is busy". With a single task on an idle pipeline, the queues admit the work
// at once: the time went into the delegate, and the breakdown should not send
// the reader to `dataLoadingQueue`.
//
// Corrected from the original repro, whose bound
// `queue <= duration - willLoadData` passed whenever the rest of the task
// happened to take longer than the delegate (a cold first decode did, in the
// first repetition). With the current code the download's queue interval
// contains the whole `willLoadData` stage, so `queue >= willLoadData` always;
// on an idle pipeline the real queue waits are a fraction of a millisecond,
// far under the 100 ms the delegate takes.
@Suite(.timeLimit(.minutes(5)))
struct DiagnosticsWillLoadDataCountedAsQueueRepro {
    @Test(arguments: [false, true])
    func delegateTimeIsNotAQueueWait(skipDataLoadingQueue: Bool) async throws {
        // GIVEN an idle pipeline with a delegate that takes 100 ms
        let pipeline = ImagePipeline(delegate: _SlowWillLoadDataDelegate()) {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
            $0.dataCache = nil
            $0.isRateLimiterEnabled = false
            $0.isDiagnosticsEnabled = true
        }
        var request = Test.request
        if skipDataLoadingQueue {
            request.options.insert(.skipDataLoadingQueue)
        }

        // WHEN
        let task = pipeline.imageTask(with: request)
        _ = try await task.response

        // THEN (precondition) the delegate took at least 100 ms
        let metrics = try #require(task.metrics)
        let fetch = try #require(metrics.jobs.last)
        let willLoadData = try #require(fetch.stages.first { $0.kind == .willLoadData }?.duration)
        try #require(willLoadData >= 0.1)

        // THEN the delegate's time is not reported as a wait for a queue
        let queue = metrics.timeShares.first { $0.category == .queue }?.duration ?? 0
        #expect(queue < willLoadData, "queue \(queue * 1000) ms of \(metrics.duration * 1000) ms for a delegate that took \(willLoadData * 1000) ms:\n\(metrics.description)")
    }
}

private final class _SlowWillLoadDataDelegate: ImagePipeline.Delegate, Sendable {
    @ImagePipelineActor
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        try await Task.sleep(for: .milliseconds(100))
        return urlRequest
    }
}

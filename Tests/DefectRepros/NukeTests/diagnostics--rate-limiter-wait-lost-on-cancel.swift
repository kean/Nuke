// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: the time a task spent held by the rate limiter disappears
// from its record when the task is cancelled before the limiter lets the
// request through: there is no `rateLimit` stage, and the wait is reported as
// `other`.
//
// Where: Sources/Nuke/Tasks/TaskFetchOriginalData.swift:51-66. The stage is
// recorded only from inside the work the limiter eventually runs:
//
//     rateLimiter.execute { [weak self] in
//         guard let self, !self.isDisposed else { return false }   // <- cancelled: nothing recorded
//         if isDeferred, let queuedAt {
//             self.diagnostics?.recordStage(.rateLimit, from: queuedAt)
//         }
//         ...
//
// A job disposed while it is pending in the limiter never records the wait,
// unlike a download waiting for `dataLoadingQueue`, which is recorded from the
// moment it is enqueued (`beginStage(.download, queued: true)`).
//
// Expected (docs): `Category.rateLimit` is "The wait in
// ImagePipeline.Configuration.rateLimiter", and `Stage.Kind.rateLimit` is "The
// time the request spent in the rate limiter". `Category.other` is for "the
// time before the pipeline started the task, the hops between the jobs, and the
// work that isn't bracketed". A task cancelled after 28 ms in the limiter
// should say `rateLimit 28 ms`.
//
// Actual: `time: other 28.5 ms (100%)`, and `j6 fetchOriginalData` has no
// stages at all – the record gives no hint that the rate limiter held it,
// which is exactly the situation (a burst of requests from a fast scroll) where
// the question comes up.
@Suite(.timeLimit(.minutes(5)))
struct DiagnosticsRateLimiterWaitRepro {
    @Test @ImagePipelineActor func waitInTheRateLimiterIsRecordedForACancelledTask() async throws {
        // GIVEN a rate limiter with a backlog long enough to hold the next
        // request for over a second
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
            $0.dataCache = nil
            $0.isDiagnosticsEnabled = true
        }
        let rateLimiter = try #require(pipeline.rateLimiter)
        let started = TestExpectation()
        pipeline.onTaskStarted = { _ in started.fulfill() }
        let task = pipeline.imageTask(with: Test.request)
        for _ in 0..<200 {
            rateLimiter.execute { true }
        }
        // The task reached the limiter in the actor turn that started it
        await started.wait()
        pipeline.onTaskStarted = nil

        // WHEN it is cancelled while the limiter holds it
        task.cancel()
        _ = try? await task.response

        // THEN (precondition) the download never started
        let metrics = try #require(task.metrics)
        let fetch = try #require(metrics.jobs.last)
        try #require(fetch.kind == .fetchOriginalData)
        try #require(!fetch.stages.contains { $0.kind == .download })

        // THEN the wait is on the record
        #expect(fetch.stages.contains { $0.kind == .rateLimit }, "No rateLimit stage in:\n\(metrics.description)")
        #expect(metrics.timeShares.contains { $0.category == .rateLimit }, "No rateLimit time in:\n\(metrics.description)")
    }
}

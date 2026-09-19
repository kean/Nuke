// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: a job created by a task the recorder skipped (the runtime
// switch `pipeline.diagnostics.isEnabled` was off when it started) names the
// first *recorded* task that joined it as its creator, so the joining task's
// copy of the job contradicts itself: `joinedAt != nil` ("the task's chain
// didn't create the job") and `createdByTaskID == <that task>` ("the task
// whose request created the job").
//
// Where: Sources/Nuke/Diagnostics/DiagnosticsRecorder.swift:343
// (`JobRecord.makeSnapshot`):
//
//     copy.createdByTaskID = joins.first?.taskID ?? 0
//
// `joins` holds only recorded tasks (`ImageTask.diagnosticsDidSubscribe`
// returns early for a task with no record), so when the creator wasn't
// recorded, `joins.first` is a task that joined – its `joinedAt` is set.
//
// Expected: `Job.createdByTaskID` is "The task whose request created the
// job"; when that task isn't known (it wasn't recorded), the field shouldn't
// name a task that merely joined. `0` – what the record starts with – or the
// first join only when its `joinedAt` is `nil`.
//
// Actual: `createdByTaskID == recorded.taskId` for all three jobs, while the
// same copies carry `joinedAt != nil` and the task is `isCoalesced`.
@Suite(.timeLimit(.minutes(5)))
struct DiagnosticsCreatedByJoiningTaskRepro {
    @Test func jobIsNotAttributedToTheTaskThatJoinedIt() async throws {
        // GIVEN a download started by a task that isn't recorded
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }
        pipeline.diagnostics.isEnabled = false
        dataLoader.isSuspended = true
        let started = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let unrecorded = pipeline.imageTask(with: Test.request)
        await started.wait()

        // WHEN a recorded task joins it
        pipeline.diagnostics.isEnabled = true
        let joined = TestExpectation()
        pipeline.onTaskStarted = { _ in joined.fulfill() }
        let recorded = pipeline.imageTask(with: Test.request)
        await joined.wait()
        pipeline.onTaskStarted = nil
        dataLoader.isSuspended = false
        _ = try await unrecorded.response
        _ = try await recorded.response

        // THEN (precondition) the recorded task joined every job
        let metrics = try #require(recorded.metrics)
        try #require(metrics.isCoalesced)
        try #require(metrics.jobs.count == 3)
        try #require(metrics.jobs.allSatisfy { $0.joinedAt != nil })

        // THEN it isn't named as the creator of the jobs it joined
        for job in metrics.jobs {
            #expect(job.createdByTaskID != recorded.taskId, "j\(job.id) \(job.kind) says task #\(recorded.taskId) created it, and that the same task joined it at \(job.joinedAt ?? 0)")
        }
    }
}

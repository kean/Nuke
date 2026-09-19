// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import Testing
import Foundation

// SUSPECTED BUG: with the diagnostics switch flipped on while a download is in
// flight, the record of a task that *joined* that download names the task as
// the one that *created* every job in the chain.
//
// `JobRecord.makeSnapshot(for:at:)` derives `createdByTaskID` from
// `joins.first?.taskID`, assuming the first task to reach a job is the one
// that created it. That holds only if the creator was recorded. The runtime
// switch (`pipeline.diagnostics.isEnabled`) is read once per task, so a task
// started while it was off never joins its jobs; the first *recorded* task to
// reach them – one that joined halfway – is then reported as their creator,
// while the same copy stamps it with a non-nil `joinedAt`.
//
// Expected: `Job.createdByTaskID` is "The task whose request created the job"
// (task 1 here), or at least never a task that the same record says joined the
// job – `createdByTaskID == metrics.taskID` implies `joinedAt == nil`.
// Actual: every job in task 2's record says `createdByTaskID == 2` and
// `joinedAt != nil`; `taskIDs == [2]`. A trace that joins records by job id
// attributes the download to the wrong task.
//
// Location: Sources/Nuke/Diagnostics/DiagnosticsRecorder.swift:333
// (`copy.createdByTaskID = joins.first?.taskID ?? 0`).
@Suite(.timeLimit(.minutes(5)))
struct DiagnosticsCreatedByJoinedTaskRepro {
    @Test func joinedTaskIsNotReportedAsTheCreator() async throws {
        // Given a download started by a task while the switch was off
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDiagnosticsEnabled = true
        }
        pipeline.diagnostics.isEnabled = false
        let downloadStarted = TestExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let creator = pipeline.imageTask(with: Test.request)
        await downloadStarted.wait()

        // When a recorded task joins it
        pipeline.diagnostics.isEnabled = true
        let joinerStarted = TestExpectation()
        pipeline.onTaskStarted = { _ in joinerStarted.fulfill() }
        let joiner = pipeline.imageTask(with: Test.request)
        await joinerStarted.wait()
        pipeline.onTaskStarted = nil
        dataLoader.isSuspended = false
        _ = try await joiner.response
        _ = try await creator.response

        // Then
        let metrics = try #require(joiner.metrics)
        #expect(metrics.isCoalesced)
        for job in metrics.jobs {
            #expect(job.joinedAt != nil)
            #expect(job.createdByTaskID != joiner.taskId) // Fails: every job says the joiner created it
        }
    }
}

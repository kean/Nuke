// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// Suspected bug: `ImagePipeline.Delegate.imageTaskCreated(_:pipeline:)` receives
// an `ImageTask` that isn't wired yet.
//
// `ImagePipeline.makeStartedImageTask` (Sources/Nuke/Pipeline/ImagePipeline.swift:183-184)
// calls `imageTaskCreated(task, isDataTask:)` – which calls the delegate
// synchronously – *before* it assigns `task._task`, the `Task` that backs
// `ImageTask.response`. `_task` is a `nonisolated(unsafe)` implicitly unwrapped
// optional whose doc comment says it is "Set once during creation, before the
// task is handed to anyone", but the delegate is handed the task first.
//
// A delegate that starts observing the outcome of every task – a natural thing
// to do in the one delegate method that sees every task, for example for
// logging or analytics:
//
//     func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {
//         Task { log(await task.response) }
//     }
//
// races the unsynchronized write of `_task` on the creating thread, and when
// it wins the race it traps on the implicitly unwrapped `nil`
// ("Unexpectedly found nil while implicitly unwrapping an Optional value") in
// the `response` getter (Sources/Nuke/ImageTask.swift:165). Without the trap
// it's still a data race that Thread Sanitizer reports.
//
// Expected: every ImageTask the delegate receives can be awaited – `response`
// returns the task's outcome.
// Actual: `task._task` is nil while `imageTaskCreated` runs (asserted directly
// below, deterministically), so awaiting `response` from a task spawned there
// crashes the process whenever the spawned task gets to it first. The second
// test widens the window (the delegate does a bit of synchronous work after
// spawning the task) to make the crash reproducible.
@Suite(.timeLimit(.minutes(2)))
struct TaskEngineReproImageTaskCreatedBeforeWiredTests {
    @Test func taskIsWiredWhenTheDelegateReceivesIt() async throws {
        // Given
        let delegate = WiringRecordingDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }

        // When
        _ = try await pipeline.imageTask(with: Test.request).response

        // Then the task the delegate saw could already be awaited
        #expect(delegate.wasWired.value == true) // Fails: false
    }

    @Test func awaitingResponseFromImageTaskCreatedDoesNotCrash() async throws {
        // Given a delegate that awaits the outcome of every task it sees
        let delegate = ResponseAwaitingDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }

        // When
        let task = pipeline.imageTask(with: Test.request) // Crashes here, inside the spawned task
        _ = try await task.response
        await delegate.observed.wait()

        // Then
        #expect(task.status.result?.isSuccess == true)
    }
}

private final class WiringRecordingDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    let wasWired = Ref<Bool?>(nil)

    func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {
        wasWired.value = task._task != nil
    }
}

private final class ResponseAwaitingDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    let observed = TestExpectation()

    func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {
        let didStart = DispatchSemaphore(value: 0)
        let observed = self.observed
        Task.detached {
            didStart.signal()
            _ = try? await task.response
            observed.fulfill()
        }
        // Some synchronous work in the delegate, e.g. writing a log entry.
        didStart.wait()
        Thread.sleep(forTimeInterval: 0.5)
    }
}

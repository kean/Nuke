// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImageTaskTests {
    private let dataLoader: MockDataLoader
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Progress

    @Test func progressFractionIsZeroUntilTheTotalIsKnown() {
        #expect(ImageTask.Progress(completed: 0, total: 0).fraction == 0)
        #expect(ImageTask.Progress(completed: 100, total: 0).fraction == 0)
        #expect(ImageTask.Progress(completed: 10, total: -1).fraction == 0)
    }

    @Test func progressFraction() {
        #expect(ImageTask.Progress(completed: 25, total: 100).fraction == 0.25)
        #expect(ImageTask.Progress(completed: 100, total: 100).fraction == 1)
    }

    @Test func progressFractionIsClampedWhenMoreDataIsReceivedThanExpected() {
        #expect(ImageTask.Progress(completed: 200, total: 100).fraction == 1)
    }

    @Test func progressIsEmptyBeforeTheDownloadStarts() {
        // Given
        dataLoader.isSuspended = true

        // When
        let task = pipeline.imageTask(with: Test.request)

        // Then
        #expect(task.status.progress == ImageTask.Progress(completed: 0, total: 0))
        task.cancel()
    }

    // MARK: - Hashable

    @Test func taskIsEqualToItselfOnly() {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)
        let other = pipeline.imageTask(with: ImageRequest(url: URL(string: "http://test.com/other.jpeg")!))

        // Then
        #expect(task == task)
        #expect(task != other)
        #expect(task.hashValue == task.hashValue)
        #expect(Set([task, task, other]).count == 2)

        task.cancel()
        other.cancel()
    }

    // MARK: - Identifiable

    @Test func idIsStableAndUniqueAcrossPipelines() {
        // Given two pipelines that both hand out the same `taskId`
        dataLoader.isSuspended = true
        let other = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let lhs = pipeline.imageTask(with: Test.request)
        let rhs = other.imageTask(with: Test.request)

        // Then the identifiers are still distinct
        #expect(lhs.taskId == rhs.taskId)
        #expect(lhs.id == lhs.id)
        #expect(lhs.id != rhs.id)

        lhs.cancel()
        rhs.cancel()
    }

    // MARK: - CustomStringConvertible

    @Test func description() {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        // Then
        let description = task.description
        #expect(description.hasPrefix("ImageTask("))
        #expect(description.contains("id: \(task.taskId)"))
        #expect(description.contains("priority: normal"))
        #expect(description.contains("progress: 0 / 0"))
        #expect(description.contains("state: running"))

        task.cancel()
    }

    @Test func descriptionReflectsTheCancelledState() {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        // When
        task.cancel()

        // Then
        #expect(task.description.contains("state: cancelled"))
    }

    @Test func descriptionReflectsTheFinishedState() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)

        // When
        _ = try await task.response

        // Then
        #expect(task.description.contains("state: success"))
    }

    @Test func descriptionReflectsTheFailure() async throws {
        // Given
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        let task = pipeline.imageTask(with: Test.request)

        // When
        _ = try? await task.response

        // Then
        #expect(task.description.contains("state: failure("))
    }

    // MARK: - Task ID

    @Test func taskIDsIncreaseWithEveryCreatedTask() {
        // Given
        dataLoader.isSuspended = true

        // When
        let tasks = (0..<5).map { _ in pipeline.imageTask(with: Test.request) }

        // Then
        let ids = tasks.map(\.taskId)
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == ids.count)
        tasks.forEach { $0.cancel() }
    }

    /// The ID is claimed from the calling thread, without a hop to the
    /// pipeline actor, so tasks created concurrently race for it.
    @Test func taskIDsAreUniqueWhenTasksAreCreatedConcurrently() {
        // Given
        dataLoader.isSuspended = true
        let pipeline = self.pipeline
        let tasks = OSAllocatedUnfairLock(initialState: [ImageTask]())

        // When
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            let task = pipeline.imageTask(with: Test.request)
            tasks.withLock { $0.append(task) }
        }

        // Then
        let created = tasks.withLock { $0 }
        #expect(created.count == 64)
        #expect(Set(created.map(\.taskId)).count == 64)
        created.forEach { $0.cancel() }
    }

    // MARK: - Events

    @Test func eventsAreDeliveredToMultipleIndependentStreams() async throws {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        // When two streams are created for the same task
        async let first = task.events.reduce(into: [ImageTask.Event]()) { $0.append($1) }
        async let second = task.events.reduce(into: [ImageTask.Event]()) { $0.append($1) }

        while await task._streamContinuations.count < 2 {
            await Task.yield()
        }
        dataLoader.isSuspended = false

        // Then both observe the terminal event
        let (lhs, rhs) = await (first, second)
        #expect(lhs.contains { if case .finished(.success) = $0 { return true } else { return false } })
        #expect(rhs.contains { if case .finished(.success) = $0 { return true } else { return false } })
    }

    @Test func subscribingAfterTheTaskFinishesReplaysTheTerminalEvent() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // When
        var events: [ImageTask.Event] = []
        for await event in task.events {
            events.append(event)
        }

        // Then
        #expect(events.count == 1)
        #expect(events.contains { if case .finished(.success) = $0 { return true } else { return false } })
    }

    @Test func subscribingAfterTheTaskIsCancelledReplaysTheTerminalEvent() async throws {
        // Given
        dataLoader.isSuspended = true
        let task = await withSuspendedDataLoading(for: pipeline, expectedCount: 1) {
            pipeline.imageTask(with: Test.request)
        }
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }

        // When
        var events: [ImageTask.Event] = []
        for await event in task.events {
            events.append(event)
        }

        // Then
        #expect(events.count == 1)
        #expect(events.contains { if case .finished(.failure(.cancelled)) = $0 { return true } else { return false } })
    }

    /// A memory cache hit finishes the task synchronously, while the pipeline
    /// is still starting it, so even a subscription made immediately after
    /// creating the task can arrive late.
    @Test func subscribingImmediatelyDeliversTheTerminalEventOnMemoryCacheHit() async throws {
        // Given
        let imageCache = MockImageCache()
        imageCache[Test.request] = Test.container
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }

        // When
        let task = pipeline.imageTask(with: Test.request)
        var events: [ImageTask.Event] = []
        for await event in task.events {
            events.append(event)
        }

        // Then
        #expect(events.count == 1)
        #expect(events.contains { if case .finished(.success) = $0 { return true } else { return false } })
    }

    @Test func subscribingMidDownloadPrimesTheStreamWithTheCurrentProgress() async throws {
        // Given a task that already received one chunk of the image
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let task = pipeline.imageTask(with: Test.request)
        while task.status.progress.completed == 0 {
            await Task.yield()
        }
        let progress = task.status.progress

        // When the stream is created after the first chunk is delivered
        async let recorded = task.events.reduce(into: [ImageTask.Event]()) { $0.append($1) }
        while await task._streamContinuations.isEmpty {
            await Task.yield()
        }
        dataLoader.resumeServingChunks(dataLoader.chunks.count)

        // Then it starts with the progress reported before it was created
        let events = await recorded
        var firstProgress: ImageTask.Progress?
        if case .progress(let value) = try #require(events.first) {
            firstProgress = value
        }
        #expect(firstProgress == progress)
        #expect(events.contains { if case .finished(.success) = $0 { return true } else { return false } })
    }

    // MARK: - Status

    @Test func statusCanBeCreatedByClients() {
        // Given a status built without a pipeline
        let status = ImageTask.Status()

        // Then
        #expect(status.result == nil)
        #expect(!status.isCancelled)
        #expect(status.priority == .normal)
        #expect(status.progress == ImageTask.Progress(completed: 0, total: 0))
    }

    @Test func statusResultIsSetWhenTheTaskFinishes() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)

        // When
        _ = try await task.response

        // Then
        #expect(task.status.result?.isSuccess == true)
    }

    @Test func statusIsCapturedAtomically() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)

        // When
        _ = try await task.response

        // Then the result and the progress agree with each other
        let status = task.status
        #expect(status.result?.isSuccess == true)
        #expect(status.progress.fraction == 1)
    }

    @Test func cancellingAFinishedTaskDoesNotChangeItsResult() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // When
        task.cancel()

        // Then the cancellation is recorded, but the outcome is not affected
        #expect(task.isCancelled)
        #expect(task.status.result?.isSuccess == true)
    }

    @Test func cancellingTwiceIsIdempotent() {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        // When
        task.cancel()
        task.cancel()

        // Then
        #expect(task.isCancelled)
    }

    @Test func isCancelledIsSetSynchronously() {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        // When
        task.cancel()

        // Then it is visible on the calling thread, without waiting for the
        // pipeline actor to process the cancellation.
        //
        // The result is deliberately not asserted here: it is written on the
        // pipeline actor, so whether it is set yet is a race.
        #expect(task.isCancelled)
    }

    // MARK: - Priority

    @Test func priorityIsTakenFromTheRequest() {
        // Given
        dataLoader.isSuspended = true
        let request = ImageRequest(url: Test.url, priority: .high)

        // When
        let task = pipeline.imageTask(with: request)

        // Then
        #expect(task.priority == .high)
        task.cancel()
    }

    @Test func priorityCanBeUpdatedDynamically() {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        // When
        task.priority = .veryHigh
        task.priority = .veryHigh // Setting the same value again is a no-op

        // Then
        #expect(task.priority == .veryHigh)
        task.cancel()
    }

    @Test func priorityCanBeUpdatedAfterTheTaskFinishes() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // When
        task.priority = .veryLow

        // Then
        #expect(task.priority == .veryLow)
    }

    /// The pipeline starts the task on its actor, after `imageTask(with:)`
    /// returns. A priority set in between has to be the one the work is
    /// scheduled with – not the priority of the request, corrected later by
    /// the update, which reaches the pipeline before there is any work to
    /// update.
    @Test @ImagePipelineActor func priorityChangedBeforeTheTaskStartsIsUsedToScheduleTheWork() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        var enqueuedPriorities: [TaskPriority] = []
        let didEnqueue = TestExpectation()
        queue.onEvent = { event in
            switch event {
            case .enqueued(let operation):
                enqueuedPriorities.append(operation.priority)
                didEnqueue.fulfill()
            default: break
            }
        }

        // When the priority changes while the test still holds the actor, so
        // the pipeline can't have started the task yet
        let task = pipeline.imageTask(with: ImageRequest(url: Test.url, priority: .low))
        task.priority = .veryHigh
        await didEnqueue.wait()
        await Task { @ImagePipelineActor in }.value // Let the update land, too

        // Then the download is enqueued with the new priority right away
        #expect(enqueuedPriorities == [.veryHigh])
        #expect(task.request.priority == .low)
        queue.isSuspended = false
        _ = try await task.response
    }

    // MARK: - Awaiting the Response

    @Test func everyAwaiterGetsTheSameResponse() async throws {
        // Given several callers awaiting the same task
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        // When
        let dataLoader = self.dataLoader
        let responses = try await withThrowingTaskGroup(of: ImageResponse.self) { group in
            for _ in 0..<5 {
                group.addTask { try await task.response }
            }
            dataLoader.isSuspended = false
            return try await group.reduce(into: [ImageResponse]()) { $0.append($1) }
        }
        let late = try await task.response

        // Then everyone, including a caller that arrives after the task
        // finished, gets the same image
        #expect(responses.count == 5)
        #expect(responses.allSatisfy { $0.image === late.image })
    }

    @Test func cancellingOneAwaitingSwiftTaskCancelsTheTaskForEveryAwaiter() async throws {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)
        let first = Task { try await task.response }
        let second = Task { try await task.response }

        // When
        first.cancel()

        // Then
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await second.value
        }
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await first.value
        }
        #expect(task.isCancelled)
    }

    /// Awaiting from a cancelled Swift task requests the cancellation right
    /// away, but a task that already finished keeps its outcome – the caller
    /// still gets it, like everyone else.
    @Test func awaitingAFinishedTaskFromACancelledSwiftTaskReturnsItsResponse() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)
        let expected = try await task.response

        // When
        let gate = AsyncGate()
        let awaiter = Task {
            await gate.wait()
            return try await task.response
        }
        awaiter.cancel()
        gate.open()
        let response = try await awaiter.value

        // Then
        #expect(response.image === expected.image)
        #expect(task.isCancelled)
        #expect(task.status.result?.isSuccess == true)
    }

    // MARK: - Streams

    @Test func progressAndPreviewsOfAFinishedTaskEndWithoutValues() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // When
        var progress: [ImageTask.Progress] = []
        for await value in task.progress {
            progress.append(value)
        }
        var previews: [ImageResponse] = []
        for await value in task.previews {
            previews.append(value)
        }

        // Then the replayed terminal event ends them both
        #expect(progress.isEmpty)
        #expect(previews.isEmpty)
    }

    @Test func streamBuffersEveryEventForAConsumerThatStartsReadingLate() async throws {
        // Given a stream registered before the download starts
        dataLoader.isSuspended = true
        dataLoader.results[Test.url] = .success((Test.data, Test.urlResponse))
        let task = pipeline.imageTask(with: Test.request)
        let events = task.events
        while await task._streamContinuations.isEmpty {
            await Task.yield()
        }

        // When nobody reads from it until the task is over
        dataLoader.isSuspended = false
        let response = try await task.response
        var recorded: [ImageTask.Event] = []
        for await event in events {
            recorded.append(event)
        }

        // Then every event is still there, in the order it was sent
        let total = Int64(Test.data.count)
        #expect(recorded == [
            .progress(ImageTask.Progress(completed: total / 2, total: total)),
            .progress(ImageTask.Progress(completed: total, total: total)),
            .finished(.success(response))
        ])
    }

    @Test func streamThatIsObservedWhenTheTaskIsCancelledEndsWithTheCancellation() async throws {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)
        let events = task.events
        while await task._streamContinuations.isEmpty {
            await Task.yield()
        }

        // When
        task.cancel()
        var recorded: [ImageTask.Event] = []
        for await event in events {
            recorded.append(event)
        }

        // Then
        #expect(recorded == [.finished(.failure(.cancelled))])
    }

    // MARK: - Status

    /// "The result is recorded immediately before the finished event is sent,
    /// so it is guaranteed to be available to the observers of that event."
    /// The delegate observes the events synchronously, as they are sent.
    @Test func statusIsUpToDateWhenEachEventIsSent() async throws {
        // Given
        let delegate = StatusRecordingDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        dataLoader.results[Test.url] = .success((Test.data, Test.urlResponse))

        // When
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then every event agrees with the status captured when it was sent
        let recorded = delegate.recorded.withLock { $0 }
        #expect(recorded.count == 3)
        for (event, status) in recorded {
            switch event {
            case .progress(let progress):
                #expect(status.progress == progress)
                #expect(status.result == nil)
            case .finished(let result):
                #expect(result.value?.image === response.image)
                #expect(status.result?.value?.image === response.image)
            case .preview:
                Issue.record("Unexpected preview")
            }
        }
    }
}

private final class StatusRecordingDelegate: ImagePipeline.Delegate, Sendable {
    let recorded = OSAllocatedUnfairLock(initialState: [(ImageTask.Event, ImageTask.Status)]())

    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        let status = task.status
        recorded.withLock { $0.append((event, status)) }
    }
}

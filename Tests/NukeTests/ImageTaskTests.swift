// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
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

    // MARK: - Events

    @Test func eventsAreDeliveredToMultipleIndependentStreams() async throws {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        // When two streams are created for the same task
        let firstStream = task.events
        let secondStream = task.events
        dataLoader.isSuspended = false
        async let first = firstStream.reduce(into: [ImageTask.Event]()) { $0.append($1) }
        async let second = secondStream.reduce(into: [ImageTask.Event]()) { $0.append($1) }

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
        let stream = task.events
        // The mock served the first chunk on the main queue, and nothing else
        // synchronizes its state.
        DispatchQueue.main.async {
            dataLoader.resumeServingChunks(dataLoader.chunks.count)
        }

        // Then it starts with the progress reported before it was created
        let events = await stream.reduce(into: [ImageTask.Event]()) { $0.append($1) }
        var firstProgress: ImageTask.Progress?
        if case .progress(let value) = try #require(events.first) {
            firstProgress = value
        }
        #expect(firstProgress == progress)
        #expect(events.contains { if case .finished(.success) = $0 { return true } else { return false } })
    }

    /// A stream is registered by the time `events` returns, so it receives the
    /// events that the pipeline sends right after, even in the same job on its
    /// actor.
    @Test @ImagePipelineActor func streamReceivesEveryEventSentAfterItIsCreated() async throws {
        // Given a started task that waits for the data
        dataLoader.isSuspended = true
        let started = TestExpectation()
        pipeline.onTaskStarted = { _ in started.fulfill() }
        let task = pipeline.imageTask(with: Test.request)
        await started.wait()

        // When the pipeline sends events right after the stream is created
        let stream = task.events
        let preview = ImageResponse(container: ImageContainer(image: Test.image, isPreview: true), request: Test.request)
        task._process(.progress(ImageTask.Progress(completed: 1, total: 2)))
        task._process(.value(preview, isCompleted: false))
        task._process(.progress(ImageTask.Progress(completed: 2, total: 2)))
        task._cancelTask()

        // Then it receives all of them, in order
        var events: [String] = []
        for await event in stream {
            switch event {
            case .progress(let progress): events.append("progress(\(progress.completed))")
            case .preview: events.append("preview")
            case .finished(.failure(.cancelled)): events.append("cancelled")
            case .finished: events.append("finished")
            }
        }
        #expect(events == ["progress(1)", "preview", "progress(2)", "cancelled"])
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
}

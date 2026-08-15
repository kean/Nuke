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

    @Test func currentProgressIsEmptyBeforeTheDownloadStarts() {
        // Given
        dataLoader.isSuspended = true

        // When
        let task = pipeline.imageTask(with: Test.request)

        // Then
        #expect(task.currentProgress == ImageTask.Progress(completed: 0, total: 0))
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

    // MARK: - Events

    @Test func startedIsTheFirstEventDeliveredToTheStream() async throws {
        // Given a stream created before the pipeline starts the task
        let observer = ImagePipelineObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let stream = Nuke.Mutex<AsyncStream<ImageTask.Event>?>(value: nil)
        observer.onTaskCreated = { task in
            stream.withLock { $0 = task.events }
        }

        // When
        _ = try await pipeline.imageTask(with: Test.request).response

        // Then
        var events: [ImageTask.Event] = []
        for await event in try #require(stream.value) {
            events.append(event)
        }
        #expect(events.first == .started)
        #expect(events.filter { $0 == .started }.count == 1)

        // Then the delegate receives it exactly once
        await Task { @ImagePipelineActor in }.value
        #expect(observer.startedTaskCount == 1)
    }

    @Test func startedIsTheFirstEventDeliveredToTheEventClosure() async throws {
        // Given
        let events = Nuke.Mutex<[ImageTask.Event]>(value: [])

        // When
        let task = pipeline.makeStartedImageTask(with: Test.request) { event, _ in
            events.withLock { $0.append(event) }
        }
        _ = try await task.response

        // Then
        let recorded = events.value
        #expect(recorded.first == .started)
        #expect(recorded.filter { $0 == .started }.count == 1)
    }

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

    /// Subscribing after the task is already finished produces an empty stream:
    /// the terminal event is not replayed.
    @Test func subscribingAfterTheTaskFinishesProducesAnEmptyStream() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // When
        var events: [ImageTask.Event] = []
        for await event in task.events {
            events.append(event)
        }

        // Then
        #expect(events.isEmpty)
    }

    @Test func subscribingAfterTheTaskIsCancelledProducesAnEmptyStream() async throws {
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
        #expect(events.isEmpty)
    }

    // MARK: - State

    @Test func stateIsCompletedWhenTheTaskFinishes() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)

        // When
        _ = try await task.response

        // Then
        #expect(task.state == .completed)
    }

    @Test func cancellingAFinishedTaskDoesNotChangeItsState() async throws {
        // Given
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // When
        task.cancel()

        // Then
        #expect(task.state == .completed)
    }

    @Test func cancellingTwiceIsIdempotent() {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        // When
        task.cancel()
        task.cancel()

        // Then
        #expect(task.state == .cancelled)
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

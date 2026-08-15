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

    /// A stream created right after the task – the pipeline hasn't started it
    /// yet, so `.started` is delivered when it is sent.
    @Test func startedIsTheFirstEventInTheStream() async throws {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.imageTask(with: Test.request)

        // When
        async let events = task.events.reduce(into: [ImageTask.Event]()) { $0.append($1) }
        while await task._streamContinuations.isEmpty {
            await Task.yield()
        }
        dataLoader.isSuspended = false

        // Then
        let received = await events
        #expect(received.first.map(isStarted) == true)
        #expect(received.count(where: isStarted) == 1)
        #expect(received.last.map { if case .finished(.success) = $0 { true } else { false } } == true)
    }

    /// A stream created after the pipeline started the task still sees
    /// `.started` – it is replayed.
    @Test func startedIsReplayedForLateSubscribers() async throws {
        // Given a task that the pipeline has already started
        dataLoader.isSuspended = true
        let didStart = TestExpectation()
        pipeline.onTaskStarted = { _ in didStart.fulfill() }
        let task = pipeline.imageTask(with: Test.request)
        await didStart.wait()
        pipeline.onTaskStarted = nil

        // When
        async let events = task.events.reduce(into: [ImageTask.Event]()) { $0.append($1) }
        while await task._streamContinuations.isEmpty {
            await Task.yield()
        }
        dataLoader.isSuspended = false

        // Then
        let received = await events
        #expect(received.first.map(isStarted) == true)
        #expect(received.count(where: isStarted) == 1)
    }

    @Test func startedIsDeliveredToTheEventClosure() async throws {
        // Given
        let recorder = EventRecorder()
        let task = pipeline.makeStartedImageTask(with: Test.request) { event, _ in
            recorder.append(event)
        }

        // When
        _ = try await task.response

        // Then
        let received = recorder.events
        #expect(received.first.map(isStarted) == true)
        #expect(received.count(where: isStarted) == 1)
    }

    @Test func startedIsDeliveredForDataTasks() async throws {
        // Given
        dataLoader.isSuspended = true
        let task = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true)

        // When
        async let events = task.events.reduce(into: [ImageTask.Event]()) { $0.append($1) }
        while await task._streamContinuations.isEmpty {
            await Task.yield()
        }
        dataLoader.isSuspended = false

        // Then
        let received = await events
        #expect(received.first.map(isStarted) == true)
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

// MARK: - Helpers

private func isStarted(_ event: ImageTask.Event) -> Bool {
    if case .started = event { return true }
    return false
}

/// Collects the events delivered to an `onEvent` closure.
private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [ImageTask.Event] = []

    var events: [ImageTask.Event] {
        lock.withLock { _events }
    }

    func append(_ event: ImageTask.Event) {
        lock.withLock { _events.append(event) }
    }
}

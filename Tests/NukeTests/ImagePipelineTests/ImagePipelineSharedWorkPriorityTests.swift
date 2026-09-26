// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// "The work only gets canceled when all the registered requests are, and the
/// priority is based on the highest priority of the registered requests."
@Suite(.timeLimit(.minutes(5))) @ImagePipelineActor
struct ImagePipelineSharedWorkPriorityTests {
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

    @Test func sharedDownloadFollowsTheHighestPriorityAndDropsWhenThatTaskIsCancelled() async throws {
        // Given a low-priority download waiting for a slot
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        var lowTask: ImageTask?
        let operations = await queue.waitForOperations(count: 1) {
            lowTask = pipeline.imageTask(with: ImageRequest(url: Test.url, priority: .low))
        }
        let operation = try #require(operations.first)
        #expect(operation.priority == .low)

        // When a high-priority task joins it
        var highTask: ImageTask?
        await waitForPriorityChange(of: operation, to: .high) {
            highTask = pipeline.imageTask(with: ImageRequest(url: Test.url, priority: .high))
        }

        // And then leaves
        await waitForPriorityChange(of: operation, to: .low) {
            highTask?.cancel()
        }

        // Then the download goes back to the priority of the remaining task,
        // which still gets its image
        #expect(!operation.isCancelled)
        queue.isSuspended = false
        _ = try await lowTask?.response
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func sharedDownloadFollowsPriorityChangesOfEveryTask() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        var first: ImageTask?
        var second: ImageTask?
        let operations = await queue.waitForOperations(count: 1) {
            first = pipeline.imageTask(with: ImageRequest(url: Test.url, priority: .normal))
            second = pipeline.imageTask(with: ImageRequest(url: Test.url, priority: .high))
        }
        let operation = try #require(operations.first)
        // The second task may join the download after it's enqueued
        await waitForPriorityChange(of: operation, to: .high) {}

        // When the task with the highest priority lowers it
        await waitForPriorityChange(of: operation, to: .normal) {
            second?.priority = .veryLow
        }

        // And the other one raises it
        await waitForPriorityChange(of: operation, to: .veryHigh) {
            first?.priority = .veryHigh
        }

        // Then
        #expect(operation.priority == .veryHigh)
        queue.isSuspended = false
        _ = try await first?.response
        _ = try await second?.response
        #expect(dataLoader.createdTaskCount == 1)
    }

    /// A request with processors sits on top of a chain of tasks: one per
    /// processor, then decoding, then the download. A priority change has to
    /// travel all the way down.
    @Test func priorityChangeReachesTheDownloadThroughEveryProcessingStage() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        let processors = MockProcessorFactory()
        let request = ImageRequest(url: Test.url, processors: [processors.make(id: "1"), processors.make(id: "2")])
        var task: ImageTask?
        let operations = await queue.waitForOperations(count: 1) {
            task = pipeline.imageTask(with: request)
        }
        let operation = try #require(operations.first)

        // When/Then
        await waitForPriorityChange(of: operation, to: .veryHigh) {
            task?.priority = .veryHigh
        }
        queue.isSuspended = false
        let response = try await task?.response
        #expect(response?.image.nk_test_processorIDs == ["1", "2"])
    }
}

/// With one download slot, the order in which the pipeline hands the requests
/// to the data loader is the order in which the queue schedules them.
@Suite(.timeLimit(.minutes(5))) @ImagePipelineActor
struct ImagePipelineSchedulingOrderTests {
    private let dataLoader: MockDataLoader
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)
            // Hands every request to the queue immediately
            $0.isRateLimiterEnabled = false
        }
    }

    @Test func pendingDownloadsStartInTheOrderOfTheirPriority() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        var tasks: [ImageTask] = []
        _ = await queue.waitForOperations(count: 3) {
            tasks.append(pipeline.imageTask(with: ImageRequest(url: url("low"), priority: .low)))
            tasks.append(pipeline.imageTask(with: ImageRequest(url: url("high"), priority: .high)))
            tasks.append(pipeline.imageTask(with: ImageRequest(url: url("normal"), priority: .normal)))
        }

        // When
        queue.isSuspended = false
        for task in tasks {
            _ = try await task.response
        }

        // Then
        #expect(dataLoader.requestedURLs == [url("high"), url("normal"), url("low")])
    }

    @Test func raisingThePriorityOfAPendingTaskMovesItsDownloadAhead() async throws {
        // Given three downloads with the same priority waiting for the slot
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        var tasks: [ImageTask] = []
        let operations = await queue.waitForOperations(count: 3) {
            for name in ["a", "b", "c"] {
                tasks.append(pipeline.imageTask(with: url(name)))
            }
        }
        // The tasks start in the order they were created, and each one
        // enqueues its download as it starts.
        let lastOperation = try #require(operations.last)

        // When the last one needs its image first
        await waitForPriorityChange(of: lastOperation, to: .veryHigh) {
            tasks[2].priority = .veryHigh
        }
        queue.isSuspended = false
        for task in tasks {
            _ = try await task.response
        }

        // Then
        #expect(dataLoader.requestedURLs.first == url("c"))
        #expect(Set(dataLoader.requestedURLs) == Set(["a", "b", "c"].map { url($0) }))
    }

    // MARK: - Helpers

    private func url(_ name: String) -> URL {
        URL(string: "http://test.com/\(name).jpeg")!
    }
}

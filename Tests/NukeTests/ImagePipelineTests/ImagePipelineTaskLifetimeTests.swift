// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// The pipeline retains every ``ImageTask`` in an internal list until the task
/// finishes. These tests cover the requests that finish _synchronously_ – while
/// the pipeline is still starting them – to make sure they don't stay in the
/// list forever, pinning the responses they hold.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineTaskLifetimeTests {
    private let dataLoader: MockDataLoader
    private let imageCache: MockImageCache
    private let dataCache: MockDataCache
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let dataCache = MockDataCache()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.dataCache = dataCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
    }

    // MARK: - Asynchronous Completion (Baseline)

    @Test func taskIsRemovedWhenRequestFinishes() async throws {
        // When
        _ = try await pipeline.image(for: Test.request)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(await pipeline.taskCount == 0)
    }

    @Test func taskIsRemovedWhenRequestFails() async throws {
        // Given
        dataLoader.results[Test.url] = .failure(URLError(.unknown) as NSError)

        // When
        await #expect(throws: (any Error).self) {
            try await pipeline.image(for: Test.request)
        }

        // Then
        #expect(await pipeline.taskCount == 0)
    }

    @Test func taskIsRemovedWhenRequestIsCancelled() async throws {
        // Given
        dataLoader.isSuspended = true

        // When
        let task = await withSuspendedDataLoading(for: pipeline, expectedCount: 1) {
            pipeline.imageTask(with: Test.request)
        }
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }

        // Then
        #expect(await pipeline.taskCount == 0)
    }

    // MARK: - Synchronous Completion

    @Test func taskIsRemovedOnMemoryCacheHit() async throws {
        // Given an image in the memory cache, `TaskLoadImage` finishes the task
        // synchronously, before the pipeline adds it to the list
        imageCache[Test.request] = Test.container

        // When
        _ = try await pipeline.image(for: Test.request)

        // Then
        #expect(dataLoader.createdTaskCount == 0)
        #expect(await pipeline.taskCount == 0)
    }

    @Test func tasksDontAccumulateOnRepeatedMemoryCacheHits() async throws {
        // Given
        imageCache[Test.request] = Test.container

        // When
        for _ in 0..<10 {
            _ = try await pipeline.image(for: Test.request)
        }

        // Then the pipeline doesn't grow the list with every warm-cache request
        #expect(await pipeline.taskCount == 0)
    }

    @Test func taskIsRemovedOnDiskCacheHitForDataRequest() async throws {
        // Given cached data, `TaskLoadData` finishes the task synchronously
        dataCache.store[Test.url.absoluteString] = Test.data

        // When
        _ = try await pipeline.data(for: Test.request)

        // Then
        #expect(dataLoader.createdTaskCount == 0)
        #expect(await pipeline.taskCount == 0)
    }

    @Test func taskIsRemovedWhenCachedDataIsMissing() async throws {
        // Given
        var request = Test.request
        request.options.insert(.returnCacheDataDontLoad)

        // When
        await #expect(throws: ImagePipeline.Error.dataMissingInCache) {
            try await pipeline.image(for: request)
        }

        // Then
        #expect(dataLoader.createdTaskCount == 0)
        #expect(await pipeline.taskCount == 0)
    }

    @Test func taskIsRemovedWhenURLIsMalformed() async throws {
        // Given a request that can't produce a `URLRequest`
        let request = ImageRequest(url: nil)

        // When
        await #expect(throws: (any Error).self) {
            try await pipeline.image(for: request)
        }

        // Then
        #expect(await pipeline.taskCount == 0)
    }

    @Test func taskIsRemovedWhenLoadingLocalResource() async throws {
        // Given a local file that the pipeline reads inline
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nuke-task-lifetime-\(UUID().uuidString).jpeg")
        try Test.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // When
        _ = try await pipeline.data(for: ImageRequest(url: url))

        // Then
        #expect(dataLoader.createdTaskCount == 0)
        #expect(await pipeline.taskCount == 0)
    }

    // MARK: - Task Deallocation

    @Test func taskIsDeallocatedAfterSynchronousCompletion() async throws {
        // Given
        imageCache[Test.request] = Test.container

        // When
        weak var weakTask: ImageTask?
        do {
            let task = pipeline.imageTask(with: Test.request)
            weakTask = task
            _ = try await task.response
        }
        await drainPipeline()

        // Then the pipeline no longer retains the task or the response it holds
        #expect(weakTask == nil)
    }

    @Test func cancelledTaskIsDeallocatedWhileTheJobItJoinedIsRunning() async throws {
        // Given two tasks waiting for the same job, which is held in the queue
        pipeline.configuration.dataLoadingQueue.isSuspended = true

        // When one of them is cancelled
        weak var weakTask1: ImageTask?
        let task2: ImageTask
        do {
            let (task1, other) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
                (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
            }
            weakTask1 = task1
            task2 = other
            task1.cancel()
            await #expect(throws: ImagePipeline.Error.cancelled) {
                try await task1.response
            }
        }
        await drainPipeline()

        // Then it isn't retained by the job the other one still waits for
        #expect(weakTask1 == nil)

        pipeline.configuration.dataLoadingQueue.isSuspended = false
        _ = try await task2.response
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func taskIsDeallocatedWhileTheJobItSharedIsStillRetained() async throws {
        // Given a task that shares its job with a request that processes the
        // job's result: the processing job retains the shared job until it
        // finishes too, and the processing is held back
        let processed = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])
        pipeline.configuration.imageProcessingQueue.isSuspended = true

        // When the shared job finishes
        weak var weakTask: ImageTask?
        let processedTask: ImageTask
        do {
            let (task, other) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
                (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: processed))
            }
            weakTask = task
            processedTask = other
            _ = try await task.response
        }
        await drainPipeline()

        // Then the finished task isn't retained along with the shared job
        #expect(dataLoader.createdTaskCount == 1)
        #expect(weakTask == nil)

        pipeline.configuration.imageProcessingQueue.isSuspended = false
        _ = try await processedTask.response
    }

    // MARK: - Events

    @Test func startedEventIsDeliveredBeforeFinishedOnMemoryCacheHit() async throws {
        // Given
        let observer = ImagePipelineObserver()
        let pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }
        imageCache[Test.request] = Test.container

        // When
        let response = try await pipeline.imageTask(with: Test.request).response
        await drainPipeline()

        // Then
        #expect(observer.events == [
            ImageTaskEvent.created,
            .started,
            .completed(result: .success(response))
        ])
    }

    // MARK: - Helpers

    /// Waits for the work the pipeline scheduled while starting a task.
    private func drainPipeline() async {
        await Task { @ImagePipelineActor in }.value
    }
}

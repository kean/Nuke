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

    @Test func taskIsDeallocatedAfterAsynchronousCompletion() async throws {
        // When
        weak var weakTask: ImageTask?
        do {
            let task = pipeline.imageTask(with: Test.request)
            weakTask = task
            _ = try await task.response
        }
        await drainPipeline()

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(weakTask == nil)
    }

    @Test func dataTaskIsDeallocatedAfterAsynchronousCompletion() async throws {
        // When
        weak var weakTask: ImageTask?
        do {
            let task = pipeline.makeStartedImageTask(with: Test.request, isDataTask: true)
            weakTask = task
            _ = try await task.response
        }
        await drainPipeline()

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(weakTask == nil)
    }

    @Test func taskIsDeallocatedAfterFailure() async throws {
        // Given
        dataLoader.results[Test.url] = .failure(URLError(.unknown) as NSError)

        // When
        weak var weakTask: ImageTask?
        do {
            let task = pipeline.imageTask(with: Test.request)
            weakTask = task
            await #expect(throws: (any Error).self) {
                try await task.response
            }
        }
        await drainPipeline()

        // Then
        #expect(weakTask == nil)
    }

    @Test func taskIsDeallocatedAfterCancellation() async throws {
        // Given a task waiting for the data
        dataLoader.isSuspended = true
        let started = TestExpectation()
        pipeline.onTaskStarted = { _ in started.fulfill() }

        // When
        weak var weakTask: ImageTask?
        do {
            let task = pipeline.imageTask(with: Test.request)
            weakTask = task
            await started.wait()
            task.cancel()
            await #expect(throws: ImagePipeline.Error.cancelled) {
                try await task.response
            }
        }
        await drainPipeline()

        // Then
        #expect(weakTask == nil)
    }

    @Test func taskIsDeallocatedAfterCancellationBeforeStart() async throws {
        // When the task is cancelled before the pipeline starts it
        let pipeline = pipeline
        weak var weakTask: ImageTask?
        do {
            let task = await Task { @ImagePipelineActor in
                let task = pipeline.imageTask(with: Test.request)
                task._cancelTask()
                return task
            }.value
            weakTask = task
            await #expect(throws: ImagePipeline.Error.cancelled) {
                try await task.response
            }
        }
        await drainPipeline()

        // Then
        #expect(dataLoader.createdTaskCount == 0)
        #expect(weakTask == nil)
    }

    @Test func taskIsDeallocatedWhenPipelineIsInvalidated() async throws {
        // Given a task waiting for the data
        dataLoader.isSuspended = true
        let started = TestExpectation()
        pipeline.onTaskStarted = { _ in started.fulfill() }

        // When
        weak var weakTask: ImageTask?
        do {
            let task = pipeline.imageTask(with: Test.request)
            weakTask = task
            await started.wait()
            pipeline.invalidate()
            await #expect(throws: ImagePipeline.Error.cancelled) {
                try await task.response
            }
        }
        await drainPipeline()

        // Then
        #expect(weakTask == nil)
    }

    @Test func taskIsDeallocatedWhenStartedOnInvalidatedPipeline() async throws {
        // Given
        pipeline.invalidate()
        await drainPipeline()

        // When
        weak var weakTask: ImageTask?
        do {
            let task = pipeline.imageTask(with: Test.request)
            weakTask = task
            await #expect(throws: ImagePipeline.Error.pipelineInvalidated) {
                try await task.response
            }
        }
        await drainPipeline()

        // Then
        #expect(weakTask == nil)
    }

    @Test func coalescedTasksAreDeallocated() async throws {
        // When two tasks wait for the same job
        weak var weakTask1: ImageTask?
        weak var weakTask2: ImageTask?
        do {
            let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
                (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
            }
            weakTask1 = task1
            weakTask2 = task2
            _ = try await task1.response
            _ = try await task2.response
        }
        await drainPipeline()

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(weakTask1 == nil)
        #expect(weakTask2 == nil)
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

    // MARK: - Pipeline Deallocation

    @Test func pipelineIsRetainedUntilRunningTaskFinishes() async throws {
        // Given a task waiting for the data
        dataLoader.isSuspended = true

        // When the app releases the pipeline
        weak var weakPipeline: ImagePipeline?
        let task: ImageTask
        do {
            let pipeline = ImagePipeline {
                $0.dataLoader = dataLoader
                $0.imageCache = imageCache
            }
            weakPipeline = pipeline
            let started = TestExpectation()
            pipeline.onTaskStarted = { _ in started.fulfill() }
            task = pipeline.imageTask(with: Test.request)
            await started.wait()
        }
        await drainPipeline()

        // Then the running task keeps it alive
        #expect(weakPipeline != nil)

        // When the task finishes
        dataLoader.isSuspended = false
        _ = try await task.response
        await drainPipeline()

        // Then the pipeline is released even though the app keeps the task
        #expect(weakPipeline == nil)
        withExtendedLifetime(task) {}
    }

    @Test func pipelineIsDeallocatedWhileFinishedTaskIsRetained() async throws {
        // Given
        imageCache[Test.request] = Test.container

        // When the app keeps a task after it finished
        weak var weakPipeline: ImagePipeline?
        let task: ImageTask
        do {
            let pipeline = ImagePipeline {
                $0.dataLoader = dataLoader
                $0.imageCache = imageCache
            }
            weakPipeline = pipeline
            task = pipeline.imageTask(with: Test.request)
            _ = try await task.response
        }
        await drainPipeline()

        // Then the task doesn't keep the pipeline alive
        #expect(weakPipeline == nil)
        withExtendedLifetime(task) {}
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

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

/// The pipeline retains every ``ImageTask`` in an internal list until the task
/// finishes. These tests cover the requests that finish _synchronously_ – while
/// the pipeline is still starting them – to make sure they don't stay in the
/// list forever, pinning the responses they hold.
///
/// The tests of the objects released after an asynchronous completion poll
/// with `waitUntil`: there is no callback for an object being released, and
/// the last references are dropped by the tasks the pipeline runs on its actor.
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
        // Given a task whose download is suspended
        let task = await startSuspended(for: pipeline, count: 1) {
            pipeline.imageTask(with: Test.request)
        }

        // When
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        dataLoader.isSuspended = false

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

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        await waitUntil { weakTask == nil }
    }

    // MARK: - Pipeline Deallocation

    /// "The user does not need to hold a strong reference to the pipeline."
    @Test func outstandingTaskKeepsThePipelineAliveUntilItFinishes() async throws {
        // Given a task of a pipeline that nobody else retains
        weak var weakPipeline: ImagePipeline?
        dataLoader.isSuspended = true
        let task: ImageTask
        do {
            let pipeline = ImagePipeline {
                $0.dataLoader = dataLoader
                $0.imageCache = nil
            }
            weakPipeline = pipeline
            task = pipeline.imageTask(with: Test.request)
        }
        #expect(weakPipeline != nil)

        // When
        dataLoader.isSuspended = false
        let response = try await task.response

        // Then the task finishes, and the pipeline is released after it
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
        await waitUntil { weakPipeline == nil }
    }

    @Test func cancelledTaskReleasesThePipeline() async throws {
        // Given a task that is loading data
        let dataLoader = CancellationReportingDataLoader()
        weak var weakPipeline: ImagePipeline?
        weak var weakTask: ImageTask?
        do {
            let pipeline = ImagePipeline {
                $0.dataLoader = dataLoader
                $0.imageCache = nil
            }
            weakPipeline = pipeline
            let task = pipeline.imageTask(with: Test.request)
            weakTask = task
            await dataLoader.didStart.wait()

            // When
            task.cancel()
            await #expect(throws: ImagePipeline.Error.cancelled) {
                try await task.response
            }
        }

        // Then nothing is left behind
        await waitUntil { weakTask == nil && weakPipeline == nil }
        #expect(dataLoader.isCancelled)
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

}

/// Holds the request until it's cancelled, and reports the cancellation the
/// way `DataLoading` requires: by calling the completion.
private final class CancellationReportingDataLoader: DataLoading, Sendable {
    let didStart = TestExpectation()
    private let cancellable = CompletionOnCancel()

    var isCancelled: Bool { cancellable.isCancelled }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        cancellable.completion.withLock { $0 = completion }
        didStart.fulfill()
        return cancellable
    }
}

private final class CompletionOnCancel: Cancellable {
    let completion = OSAllocatedUnfairLock<(@Sendable (Error?) -> Void)?>(initialState: nil)
    private let _isCancelled = OSAllocatedUnfairLock(initialState: false)

    var isCancelled: Bool { _isCancelled.withLock { $0 } }

    func cancel() {
        _isCancelled.withLock { $0 = true }
        completion.withLock { $0.take() }?(URLError(.cancelled))
    }
}

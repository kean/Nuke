// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Combine
@testable import Nuke

/// - note: It's important that this test is no isolated to `ImagePipelineActor`
/// as it relies on the order of `prefetcher.wait` and other calls.
@Suite struct ImagePrefetcherTests {
    private var prefetcher: ImagePrefetcher!
    private var pipeline: ImagePipeline!

    private let dataLoader = MockDataLoader()
    private let dataCache = MockDataCache()
    private var imageCache = MockImageCache()
    private let observer = ImagePipelineObserver()
    private var cancellables: [AnyCancellable] = []

    init() {
        pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
        prefetcher = ImagePrefetcher(pipeline: pipeline)
    }

    // MARK: Basics

    /// Start prefetching for the request and then request an image separarely.
    @Test func basicScenario() async throws {
        prefetcher.startPrefetching(with: [Test.request])
        _ = try await pipeline.image(for: Test.request)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(observer.createdTaskCount == 2)
    }

    // MARK: Start Prefetching

    @Test func startPrefetching() async {
        // When
        prefetcher.startPrefetching(with: [Test.url])
        await prefetcher.wait()

        // Then image saved in both caches
        #expect(pipeline.cache[Test.request] != nil)
        #expect(pipeline.cache.cachedData(for: Test.request) != nil)
    }

    @Test func startPrefetchingWithTwoEquivalentURLs() async {
        // When
        prefetcher.startPrefetching(with: [Test.url])
        prefetcher.startPrefetching(with: [Test.url])
        await prefetcher.wait()

        // Then only one task is started
        #expect(observer.createdTaskCount == 1)
    }

    // MARK: Stop Prefetching

    @Test func stopPrefetching() async {
        dataLoader.isSuspended = true

        let created = AsyncExpectation(notification: ImagePipelineObserver.didCreateTask, object: observer)
        prefetcher.startPrefetching(with: [Test.url])
        await created.wait()

        let started = AsyncExpectation(notification: ImagePipelineObserver.didCancelTask, object: observer)
        prefetcher.stopPrefetching(with: [Test.url])
        await started.wait()
    }

    // MARK: Destination

    @Test func startPrefetchingDestinationDisk() async {
        // Given
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in
                Issue.record("Expect image not to be decoded")
                return nil
            }
        }
        let prefetcher = ImagePrefetcher(pipeline: pipeline, destination: .diskCache)

        // When
        prefetcher.startPrefetching(with: [Test.url])
        await prefetcher.wait()

        // Then image saved in both caches
        #expect(pipeline.cache[Test.request] == nil)
        #expect(pipeline.cache.cachedData(for: Test.request) != nil)
    }

    // MARK: Pause

    @Test func pausingPrefetcher() async {
        // When
        prefetcher.isPaused = true
        prefetcher.startPrefetching(with: [Test.url])

        try? await Task.sleep(nanoseconds: 3 * 1_000_000)

        // Then
        #expect(observer.createdTaskCount == 0)
    }

    // MARK: Priority

    @ImagePipelineActor
    @Test func defaultPrioritySetToLow() async {
        // When start prefetching with URL
        dataLoader.isSuspended = true

        let expectation = pipeline.configuration.dataLoadingQueue.expectItemAdded()
        prefetcher.startPrefetching(with: [Test.url])
        let workItem = await expectation.wait()

        // Then priority is set to .low
        #expect(workItem.priority == .low)

        // Cleanup
        prefetcher.stopPrefetching()
    }

//    @Test func defaultPriorityAffectsRequests() {
//        // When start prefetching with ImageRequest
//        pipeline.configuration.dataLoadingQueue.isSuspended = true
//        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
//        let request = Test.request
//        #expect(request.priority == .normal) // Default is .normal // Default is .normal
//        prefetcher.startPrefetching(with: [request])
//        wait()
//
//        // Then priority is set to .low
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//        #expect(operation.queuePriority == .low)
//    }
//
//    @Test func lowerPriorityThanDefaultNotAffected() {
//        // When start prefetching with ImageRequest with .veryLow priority
//        pipeline.configuration.dataLoadingQueue.isSuspended = true
//        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
//        var request = Test.request
//        request.priority = .veryLow
//        prefetcher.startPrefetching(with: [request])
//        wait()
//
//        // Then priority is set to .low (prefetcher priority)
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//        #expect(operation.queuePriority == .low)
//    }
//
//    @Test func changePriority() {
//        // Given
//        prefetcher.priority = .veryHigh
//
//        // When
//        pipeline.configuration.dataLoadingQueue.isSuspended = true
//        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
//        prefetcher.startPrefetching(with: [Test.url])
//        wait()
//
//        // Then
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//        #expect(operation.queuePriority == .veryHigh)
//    }
//
//    @Test func changePriorityOfOutstandingTasks() {
//        // When
//        pipeline.configuration.dataLoadingQueue.isSuspended = true
//        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
//        prefetcher.startPrefetching(with: [Test.url])
//        wait()
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//
//        // When/Them
//        expect(operation).toUpdatePriority(from: .low, to: .veryLow)
//        prefetcher.priority = .veryLow
//        wait()
//    }

    // MARK: Misc

    @Test func thatAllPrefetchingRequestsAreStoppedWhenPrefetcherIsDeallocated() async {
        let cancelled = AsyncExpectation(notification: ImagePipelineObserver.didCancelTask, object: observer)
        func functionThatLeavesScope() async {
            let prefetcher = ImagePrefetcher(pipeline: pipeline)
            dataLoader.isSuspended = true

            let created = AsyncExpectation(notification: ImagePipelineObserver.didCreateTask, object: observer)
            prefetcher.startPrefetching(with: [Test.request])
            await created.wait()
        }
        await functionThatLeavesScope()
        await cancelled.wait()
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite @ImagePipelineActor struct ImagePrefetcherTests {
    private var prefetcher: ImagePrefetcher!
    private var pipeline: ImagePipeline!

    private let dataLoader = MockDataLoader()
    private let dataCache = MockDataCache()
    private var imageCache = MockImageCache()
    private let observer = ImagePipelineObserver()

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

        // THEN
        #expect(dataLoader.createdTaskCount == 1)
        #expect(observer.createdTaskCount == 2)
    }

    // MARK: Start Prefetching

    @Test func startPrefetching() async {
        // WHEN
        prefetcher.startPrefetching(with: [Test.url])
        await prefetcher.waitForCompletion()

        // THEN image saved in both caches
        #expect(pipeline.cache[Test.request] != nil)
        #expect(pipeline.cache.cachedData(for: Test.request) != nil)
    }

    @Test func startPrefetchingWithTwoEquivalentURLs() async {
        // WHEN
        prefetcher.startPrefetching(with: [Test.url])
        prefetcher.startPrefetching(with: [Test.url])
        await prefetcher.waitForCompletion()

        // THEN only one task is started
        #expect(observer.createdTaskCount == 1)
    }

    // MARK: Stop Prefetching

    @Test func stopPrefetching() {
//        dataLoader.isSuspended = true
//
//        // WHEN
//        let url = Test.url
//        expectNotification(ImagePipelineObserver.didCreateTask, object: observer)
//        prefetcher.startPrefetching(with: [url])
//        wait()
//
//        expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
//        prefetcher.stopPrefetching(with: [url])
//        wait()
    }
//
//    // MARK: Destination
//
//    @Test func startPrefetchingDestinationDisk() {
//        // GIVEN
//        pipeline = pipeline.reconfigured {
//            $0.makeImageDecoder = { _ in
//                Issue.record("Expect image not to be decoded")
//                return nil
//            }
//        }
//        prefetcher = ImagePrefetcher(pipeline: pipeline, destination: .diskCache)
//
//        expectPrefetcherToComplete()
//
//        // WHEN
//        prefetcher.startPrefetching(with: [Test.url])
//
//        wait()
//
//        // THEN image saved in both caches
//        #expect(pipeline.cache[Test.request] == nil)
//        #expect(pipeline.cache.cachedData(for: Test.request) != nil)
//    }
//
//    // MARK: Pause
//
//    @Test func pausingPrefetcher() {
//        // WHEN
//        prefetcher.isPaused = true
//        prefetcher.startPrefetching(with: [Test.url])
//
//        let expectation = self.expectation(description: "TimePassed")
//        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) {
//            expectation.fulfill()
//        }
//        wait()
//
//        // THEN
//        #expect(observer.createdTaskCount == 0)
//    }
//
//    // MARK: Priority
//
//    @Test func defaultPrioritySetToLow() {
//        // WHEN start prefetching with URL
//        pipeline.configuration.dataLoadingQueue.isSuspended = true
//        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
//        prefetcher.startPrefetching(with: [Test.url])
//        wait()
//
//        // THEN priority is set to .low
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//        #expect(operation.queuePriority == .low)
//
//        // Cleanup
//        prefetcher.stopPrefetching()
//    }
//
//    @Test func defaultPriorityAffectsRequests() {
//        // WHEN start prefetching with ImageRequest
//        pipeline.configuration.dataLoadingQueue.isSuspended = true
//        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
//        let request = Test.request
//        #expect(request.priority == .normal) // Default is .normal // Default is .normal
//        prefetcher.startPrefetching(with: [request])
//        wait()
//
//        // THEN priority is set to .low
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//        #expect(operation.queuePriority == .low)
//    }
//
//    @Test func lowerPriorityThanDefaultNotAffected() {
//        // WHEN start prefetching with ImageRequest with .veryLow priority
//        pipeline.configuration.dataLoadingQueue.isSuspended = true
//        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
//        var request = Test.request
//        request.priority = .veryLow
//        prefetcher.startPrefetching(with: [request])
//        wait()
//
//        // THEN priority is set to .low (prefetcher priority)
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//        #expect(operation.queuePriority == .low)
//    }
//
//    @Test func changePriority() {
//        // GIVEN
//        prefetcher.priority = .veryHigh
//
//        // WHEN
//        pipeline.configuration.dataLoadingQueue.isSuspended = true
//        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
//        prefetcher.startPrefetching(with: [Test.url])
//        wait()
//
//        // THEN
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//        #expect(operation.queuePriority == .veryHigh)
//    }
//
//    @Test func changePriorityOfOutstandingTasks() {
//        // WHEN
//        pipeline.configuration.dataLoadingQueue.isSuspended = true
//        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
//        prefetcher.startPrefetching(with: [Test.url])
//        wait()
//        guard let operation = observer.operations.first else {
//            return Issue.record("Failed to find operation")
//        }
//
//        // WHEN/THEN
//        expect(operation).toUpdatePriority(from: .low, to: .veryLow)
//        prefetcher.priority = .veryLow
//        wait()
//    }
//
//    // MARK: DidComplete
//
//    @Test func didCompleteIsCalled() {
//        let expectation = self.expectation(description: "PrefecherDidComplete")
//        prefetcher.didComplete = { @Sendable in
//            expectation.fulfill()
//        }
//
//        prefetcher.startPrefetching(with: [Test.url])
//        wait()
//    }
//
//    @Test func didCompleteIsCalledWhenImageCached() {
//        let expectation = self.expectation(description: "PrefecherDidComplete")
//        prefetcher.didComplete = { @Sendable in
//            expectation.fulfill()
//        }
//
//        imageCache[Test.request] = Test.container
//
//        prefetcher.startPrefetching(with: [Test.request])
//        wait()
//    }
//
//    // MARK: Misc
//
//    @Test func thatAllPrefetchingRequestsAreStoppedWhenPrefetcherIsDeallocated() {
//        pipeline.configuration.dataLoadingQueue.isSuspended = true
//
//        let request = Test.request
//        expectNotification(ImagePipelineObserver.didCreateTask, object: observer)
//        prefetcher.startPrefetching(with: [request])
//        wait()
//
//        expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
//        autoreleasepool {
//            prefetcher = nil
//        }
//        wait()
//    }
//
//    func expectPrefetcherToComplete() {
//        let expectation = self.expectation(description: "PrefecherDidComplete")
//        prefetcher.didComplete = { @Sendable in
//            expectation.fulfill()
//        }
//    }
}

private extension ImagePrefetcher {
    func waitForCompletion() async {
        await confirmation { confirmation in
            await withUnsafeContinuation { continuation in
                didComplete = {
                    continuation.resume()
                    confirmation()
                }
            }
        }
    }
}

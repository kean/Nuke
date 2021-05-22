// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

final class ImagePrefetcherTests: XCTestCase {
    private var pipeline: ImagePipeline!
    private var dataLoader: MockDataLoader!
    private var dataCache: MockDataCache!
    private var imageCache: MockImageCache!
    private var observer: ImagePipelineObserver!
    private var prefetcher: ImagePrefetcher!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        dataCache = MockDataCache()
        imageCache = MockImageCache()
        observer = ImagePipelineObserver()
        pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
        prefetcher = ImagePrefetcher(pipeline: pipeline)
    }

    override func tearDown() {
        super.tearDown()

        observer = nil
    }

    // MARK: Basics

    /// Start prefetching for the request and then request an image separarely.
    func testBasicScenario() {
        dataLoader.isSuspended = true

        expect(prefetcher.queue).toEnqueueOperationsWithCount(1)
        prefetcher.startPrefetching(with: [Test.url])
        wait()

        expect(pipeline).toLoadImage(with: Test.url)
        pipeline.queue.async {
            self.dataLoader.isSuspended = false
        }
        wait()

        // THEN
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertEqual(observer.startedTaskCount, 2)
    }

    // MARK: Start Prefetching

    func testStartPrefetching() {
        expectPrefetcherToComplete()

        // WHEN
        prefetcher.startPrefetching(with: [Test.url])

        wait()

        // THEN image saved in both caches
        XCTAssertNotNil(pipeline.cache[Test.url])
        XCTAssertNotNil(pipeline.cache.cachedData(for: Test.url))
    }

    func testStartPrefetchingWithTwoEquivalentURLs() {
        dataLoader.isSuspended = true
        expectPrefetcherToComplete()

        // WHEN
        prefetcher.startPrefetching(with: [Test.url])
        prefetcher.startPrefetching(with: [Test.url])

        pipeline.queue.async {
            self.dataLoader.isSuspended = false
        }
        wait()

        // THEN only one task is started
        XCTAssertEqual(observer.startedTaskCount, 1)
    }

    func testWhenImageIsInMemoryCacheNoTaskStarted() {
        dataLoader.isSuspended = true

        // GIVEN
        pipeline.cache[Test.url] = Test.container

        // WHEN
        prefetcher.startPrefetching(with: [Test.url])
        pipeline.queue.sync {}

        // THEN
        XCTAssertEqual(observer.startedTaskCount, 0)
    }

    // MARK: Stop Prefetching

    func testStopPrefetching() {
        dataLoader.isSuspended = true

        // WHEN
        let url = Test.url
        expectNotification(ImagePipelineObserver.didStartTask, object: observer)
        prefetcher.startPrefetching(with: [url])
        wait()

        expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
        prefetcher.stopPrefetching(with: [url])
        wait()
    }

    // MARK: Destination

    func testStartPrefetchingDestinationDisk() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in
                XCTFail("Expect image not to be decoded")
                return nil
            }
        }
        prefetcher = ImagePrefetcher(pipeline: pipeline, destination: .diskCache)

        expectPrefetcherToComplete()

        // WHEN
        prefetcher.startPrefetching(with: [Test.url])

        wait()

        // THEN image saved in both caches
        XCTAssertNil(pipeline.cache[Test.url])
        XCTAssertNotNil(pipeline.cache.cachedData(for: Test.url))
    }

    // MARK: Pause

    func testPausingPrefetcher() {
        // WHEN
        prefetcher.isPaused = true
        prefetcher.startPrefetching(with: [Test.url])

        let expectation = self.expectation(description: "TimePassed")
        pipeline.queue.asyncAfter(deadline: .now() + .milliseconds(10)) {
            expectation.fulfill()
        }
        wait()

        // THEN
        XCTAssertEqual(observer.startedTaskCount, 0)
    }

    // MARK: Priority

    func testDefaultPrioritySetToLow() {
        // WHEN start prefetching with URL
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
        prefetcher.startPrefetching(with: [Test.url])
        wait()

        // THEN priority is set to .low
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        XCTAssertEqual(operation.queuePriority, .low)

        // Cleanup
        prefetcher.stopPrefetching()
    }

    func testDefaultPriorityAffectsRequests() {
        // WHEN start prefetching with ImageRequest
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
        let request = Test.request
        XCTAssertEqual(request.priority, .normal) // Default is .normal
        prefetcher.startPrefetching(with: [request])
        wait()

        // THEN priority is set to .low
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        XCTAssertEqual(operation.queuePriority, .low)
    }

    func testLowerPriorityThanDefaultNotAffected() {
        // WHEN start prefetching with ImageRequest with .veryLow priority
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
        var request = Test.request
        request.priority = .veryLow
        prefetcher.startPrefetching(with: [request])
        wait()

        // THEN priority is set to .low (prefetcher priority)
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        XCTAssertEqual(operation.queuePriority, .low)
    }

    func testChangePriority() {
        // GIVEN
        prefetcher.priority = .veryHigh

        // WHEN
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
        prefetcher.startPrefetching(with: [Test.url])
        wait()

        // THEN
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        XCTAssertEqual(operation.queuePriority, .veryHigh)
    }

    func testChangePriorityOfOutstandingTasks() {
        // WHEN
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
        prefetcher.startPrefetching(with: [Test.url])
        wait()
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }

        // WHEN/THEN
        expect(operation).toUpdatePriority(from: .low, to: .veryLow)
        prefetcher.priority = .veryLow
        wait()
    }

    // MARK: Misc

    func testThatAllPrefetchingRequestsAreStoppedWhenPrefetcherIsDeallocated() {
        pipeline.configuration.dataLoadingQueue.isSuspended = true

        let request = Test.request
        expectNotification(ImagePipelineObserver.didStartTask, object: observer)
        prefetcher.startPrefetching(with: [request])
        wait()

        expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
        autoreleasepool {
            prefetcher = nil
        }
        wait()
    }

    func expectPrefetcherToComplete() {
        let expectation = self.expectation(description: "PrefecherDidComplete")
        prefetcher.didComplete = {
            expectation.fulfill()
        }
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePrefetcherTests: XCTestCase {
    var pipeline: MockImagePipeline!
    var prefetcher: ImagePrefetcher!

    override func setUp() {
        super.setUp()

        pipeline = MockImagePipeline {
            $0.imageCache = nil
        }
        prefetcher = ImagePrefetcher(pipeline: pipeline)
    }

    // MARK: Starting Prefetching

    func testStartPrefetchingWithTheSameRequests() {
        pipeline.operationQueue.isSuspended = true

        // When starting prefetching for the same requests (same cacheKey, loadKey).
        expect(pipeline.operationQueue).toFinishWithEnqueuedOperationCount(1)

        let request = Test.request
        prefetcher.startPrefetching(with: [request])
        prefetcher.startPrefetching(with: [request])

        wait()
    }

    func testStartPrefetchingWithDifferentProcessors() {
        pipeline.operationQueue.isSuspended = true

        // When starting prefetching for the requests with the same URL (same loadKey)
        // but different processors (different cacheKey).
        expect(pipeline.operationQueue).toFinishWithEnqueuedOperationCount(2)

        prefetcher.startPrefetching(with: [ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })])])
        prefetcher.startPrefetching(with: [ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "2", { $0 })])])

        wait()
    }

    func testStartPrefetchingSameProcessorsDifferentURLRequests() {
        pipeline.operationQueue.isSuspended = true

        // When starting prefetching for the requests with the same URL, but
        // different URL requests (different loadKey) but the same processors
        // (same cacheKey).
        expect(pipeline.operationQueue).toFinishWithEnqueuedOperationCount(2)

        prefetcher.startPrefetching(with: [ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 100))])
        prefetcher.startPrefetching(with: [ImageRequest(urlRequest: URLRequest(url: Test.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 100))])

        wait()
    }

    func testStartingPrefetchingWithURLS() {
        pipeline.operationQueue.isSuspended = true

        expect(pipeline.operationQueue).toFinishWithEnqueuedOperationCount(1)

        prefetcher.startPrefetching(with: [Test.url])

        wait()
    }

    // MARK: Stoping Prefetching

    func testStopPrefetchingWithURLs() {
        pipeline.operationQueue.isSuspended = true

        let url = Test.url
        _ = expectNotification(MockImagePipeline.DidStartTask, object: pipeline)
        prefetcher.startPrefetching(with: [url])
        wait()

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        prefetcher.stopPrefetching(with: [url])
        wait()
    }

    func testThatPrefetchingRequestsAreStopped() {
        pipeline.operationQueue.isSuspended = true

        let request = Test.request
        _ = expectNotification(MockImagePipeline.DidStartTask, object: pipeline)
        prefetcher.startPrefetching(with: [request])
        wait()

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        prefetcher.stopPrefetching(with: [request])
        wait()
    }

    func testThatEquaivalentRequestsAreStoppedWithSingleStopCall() {
        pipeline.operationQueue.isSuspended = true

        let request = Test.request
        _ = expectNotification(MockImagePipeline.DidStartTask, object: pipeline)
        prefetcher.startPrefetching(with: [request, request])
        wait()

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        prefetcher.stopPrefetching(with: [request])

        wait { _ in
            XCTAssertEqual(self.pipeline.createdTaskCount, 1, "")
        }
    }

    func testThatAllPrefetchingRequestsAreStopped() {
        pipeline.operationQueue.isSuspended = true

        let request = Test.request
        _ = expectNotification(MockImagePipeline.DidStartTask, object: pipeline)
        prefetcher.startPrefetching(with: [request])
        wait()

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        prefetcher.stopPrefetching()
        wait()
    }

    func testThatAllPrefetchingRequestsAreStoppedWhenPrefetcherIsDeallocated() {
        pipeline.operationQueue.isSuspended = true

        let request = Test.request
        _ = expectNotification(MockImagePipeline.DidStartTask, object: pipeline)
        prefetcher.startPrefetching(with: [request])
        wait()

        _ = expectNotification(MockImagePipeline.DidCancelTask, object: pipeline)
        autoreleasepool {
            prefetcher = nil
        }
        wait()
    }

    // MARK: Integration Tests

    func testIntegration() {
        // Given
        let pipeline = ImagePipeline()
        let preheater = ImagePrefetcher(pipeline: pipeline, destination: .memoryCache, maxConcurrentRequestCount: 2)

        // When
        preheater.queue.isSuspended = true
        expect(preheater.queue).toFinishWithEnqueuedOperationCount(1)
        let url = Test.url(forResource: "fixture", extension: "jpeg")
        preheater.startPrefetching(with: [url])
        wait()

        // Then
        XCTAssertNotNil(pipeline.configuration.imageCache?[url])
    }
}

class ImagePrefetcherPriorityTests: XCTestCase {
    var pipeline: ImagePipeline!
    var prefetcher: ImagePrefetcher!

    override func setUp() {
        super.setUp()

        pipeline = ImagePipeline {
            $0.imageCache = nil
            $0.dataLoader = MockDataLoader()
        }
        prefetcher = ImagePrefetcher(pipeline: pipeline)
    }

    func testDefaultPrioritySetToLow() {
        // Given default prefetcher

        // When start prefetching with URL
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
        prefetcher.startPrefetching(with: [Test.url])
        wait()

        // Then priority is set to .low
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        XCTAssertEqual(operation.queuePriority, .low)

        // Cleanup
        prefetcher.stopPrefetching()
    }

    func testDefaultPriorityAffectsRequests() {
        // Given default prefetcher

        // When start prefetching with ImageRequest
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
        let request = Test.request
        XCTAssertEqual(request.priority, .normal) // Default is .normal
        prefetcher.startPrefetching(with: [request])
        wait()

        // Then priority is set to .low
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        XCTAssertEqual(operation.queuePriority, .low)
    }

    func testLowerPriorityThanDefaultNotAffected() {
        // Given default prefetcher

        // When start prefetching with ImageRequest with .veryLow priority
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
        var request = Test.request
        request.priority = .veryLow
        prefetcher.startPrefetching(with: [request])
        wait()

        // Then priority is set to .veryLow (not changed by prefetcher)
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        XCTAssertEqual(operation.queuePriority, .veryLow)
    }

    func testChangePriority() {
        // Given
        prefetcher.priority = .veryHigh

        // When
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
        prefetcher.startPrefetching(with: [Test.url])
        wait()

        // Then
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }
        XCTAssertEqual(operation.queuePriority, .veryHigh)
    }

    func testChangePriorityOfOutstandingTasks() {
        // When
        pipeline.configuration.dataLoadingQueue.isSuspended = true
        let observer = expect(pipeline.configuration.dataLoadingQueue).toEnqueueOperationsWithCount(1)
        prefetcher.startPrefetching(with: [Test.url])
        wait()
        guard let operation = observer.operations.first else {
            return XCTFail("Failed to find operation")
        }

        // When/Then
        expect(operation).toUpdatePriority(from: .low, to: .veryLow)
        prefetcher.priority = .veryLow
        wait()
    }
}

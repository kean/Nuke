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

    // MARK: - Starting Prefetching

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

    // MARK: - Stoping Prefetching

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

    func testIntegration() {
        // GIVEN
        let pipeline = ImagePipeline()
        let preheater = ImagePrefetcher(pipeline: pipeline, destination: .memoryCache, maxConcurrentRequestCount: 2)

        // WHEN
        preheater.queue.isSuspended = true
        expect(preheater.queue).toFinishWithEnqueuedOperationCount(1)
        let url = Test.url(forResource: "fixture", extension: "jpeg")
        preheater.startPrefetching(with: [url])
        wait()

        // THEN
        XCTAssertNotNil(pipeline.configuration.imageCache?[url])
    }
}

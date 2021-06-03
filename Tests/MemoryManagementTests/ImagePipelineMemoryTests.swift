// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineMemoryTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var prefetcher: ImagePrefetcher!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        prefetcher = ImagePrefetcher(pipeline: pipeline)
    }

    func expectDeinit(_ closure: () -> Void) {
        autoreleasepool {
            closure()

            pipeline = nil
            dataLoader = nil
            prefetcher = nil

            #if TRACK_ALLOCATIONS
            let allDeinitExpectation = self.expectation(description: "AllDeallocated")
            Allocations.onDeinitAll {
                allDeinitExpectation.fulfill()
            }
            #endif
        }
    }

    // MARK: - Completion

    func testBasicRequest() {
        expectDeinit {
            expect(pipeline).toLoadImage(with: Test.request) { _ in }
            wait()
        }
        wait()
    }

    // MARK: - Cancellation

    func testDataLoadingOperationCancelled() {
        expectDeinit {
            dataLoader.queue.isSuspended = true

            expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
            let task = pipeline.loadImage(with: Test.request) { _ in
                XCTFail()
            }
            wait() // Wait till operation is created

            expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
            task.cancel()
            wait()

            dataLoader.queue.isSuspended = false
        }
        wait()
    }

    func testProcessingOperationCancelled() {
        expectDeinit {
            let queue = pipeline.configuration.imageProcessingQueue
            queue.isSuspended = true

            let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

            let processor = ImageProcessors.Anonymous(id: "1") {
                XCTFail()
                return $0
            }
            let request = ImageRequest(url: Test.url, processors: [processor])

            let task = pipeline.loadImage(with: request) { _ in
                XCTFail()
            }
            wait() // Wait till operation is created

            // When/Then
            let operation = observer.operations.first
            XCTAssertNotNil(operation)
            expect(operation!).toCancel()

            task.cancel()

            wait()
            queue.isSuspended = false
        }
        wait()
    }


    // ImagePipeline retains itself until there are any pending tasks.
    func testPipelineRetainsItselfWhileTasksPending() {
        expectDeinit {
            let expectation = self.expectation(description: "ImageLoaded")
            ImagePipeline {
                $0.dataLoader = dataLoader
                $0.imageCache = nil
            }.loadImage(with: Test.request) { result in
                XCTAssertTrue(result.isSuccess)
                expectation.fulfill()
            }
            wait()
        }
        wait()
    }

    func testWhenInvalidatedTasksAreCancelledAndPipelineIsDeallocated() {
        expectDeinit {
            dataLoader.queue.isSuspended = true
            
            expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
            pipeline.loadImage(with: Test.request) { _ in
                XCTFail()
            }
            wait() // Wait till operation is created
            
            expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
            pipeline.invalidate()
            wait()
        }
        wait()
    }

    // MARK: Prefetcher

    func testPrefetcherDeallocation() {
        expectDeinit {
            let expectation = self.expectation(description: "PrefecherDidComplete")
            prefetcher.didComplete = {
                expectation.fulfill()
            }

            // WHEN
            prefetcher.startPrefetching(with: [Test.url])
            wait()
        }
        wait()
    }
}

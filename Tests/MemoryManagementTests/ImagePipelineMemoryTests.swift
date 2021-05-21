// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineMemoryTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    func waitAndDeinitPipeline() {
        pipeline = nil
        dataLoader = nil

        #if TRACK_ALLOCATIONS
        let allDeinitExpectation = self.expectation(description: "AllDeallocated")
        Allocations.onDeinitAll {
            allDeinitExpectation.fulfill()
        }
        wait()
        #endif
    }

    // MARK: - Completion

    func testCompletionCalledAsynchronouslyOnMainThread() {
        var isCompleted = false
        expect(pipeline).toLoadImage(with: Test.request) { _ in
            XCTAssert(Thread.isMainThread)
            isCompleted = true
        }
        XCTAssertFalse(isCompleted)
        wait()

        // Cleanup
        waitAndDeinitPipeline()
    }

    // MARK: - Cancellation

    func testDataLoadingOperationCancelled() {
        dataLoader.queue.isSuspended = true

        autoreleasepool {
            expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
            let task = pipeline.loadImage(with: Test.request) { _ in
                XCTFail()
            }
            wait() // Wait till operation is created

            expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
            task.cancel()
            wait()
        }

        // Cleanup
        dataLoader.queue.isSuspended = false
        waitAndDeinitPipeline()
     }

    func testDecodingOperationCancelled() {
        ImagePipeline.Configuration.isFastTrackDecodingEnabled = false
        defer { ImagePipeline.Configuration.isFastTrackDecodingEnabled = true }

        // Given
        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        autoreleasepool {
            let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

            let request = Test.request

            let task = pipeline.loadImage(with: request) { _ in
                XCTFail()
            }
            wait() // Wait till operation is created

            // When/Then
            guard let operation = observer.operations.first else {
                XCTFail("Failed to find operation")
                return
            }
            expect(operation).toCancel()

            task.cancel()

            wait()
        }

        // Cleanup
        queue.isSuspended = false
        waitAndDeinitPipeline()
    }

    func testProcessingOperationCancelled() {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        autoreleasepool {
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
        }

        // Cleanup
        queue.isSuspended = false
        waitAndDeinitPipeline()
    }


    // ImagePipeline retains itself until there are any pending tasks.
    func testPipelineRetainsItselfWhileTasksPending() {
        let expectation = self.expectation(description: "ImageLoaded")
        ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }.loadImage(with: Test.request) { result in
            XCTAssertTrue(result.isSuccess)
            expectation.fulfill()
        }
        wait()

        // Cleanup
        waitAndDeinitPipeline()
    }

    func testWhenInvalidatedTasksAreCancelledAndPipelineIsDeallocated() {
        dataLoader.queue.isSuspended = true

        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        pipeline.loadImage(with: Test.request) { _ in
            XCTFail()
        }
        wait() // Wait till operation is created

        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        pipeline.invalidate()
        wait()

        // Cleanup
        waitAndDeinitPipeline()
    }

}

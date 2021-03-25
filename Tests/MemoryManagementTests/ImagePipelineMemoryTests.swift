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

    // MARK: - Progress

    func testProgressClosureIsCalled() {
        // Given
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let expectedProgress = expectProgress([(10, 20), (20, 20)])
        let expectedCompletion = expectation(description: "ImageLoaded")

        pipeline.loadImage(
            with: ImageRequest(url: Test.url),
            progress: { _, completed, total in
                // Then
                XCTAssertTrue(Thread.isMainThread)
                expectedProgress.received((completed, total))
            },
            completion: { _ in
                expectedCompletion.fulfill()
            }
        )
        wait()

        // Cleanup
        waitAndDeinitPipeline()
    }

    // MARK: - Callback Queues

    func _testChangingCallbackQueueLoadImage() {
        // Given
        let queue = DispatchQueue(label: "testChangingCallbackQueue")
        let queueKey = DispatchSpecificKey<Void>()
        queue.setSpecific(key: queueKey, value: ())

        // When/Then
        let expectation = self.expectation(description: "Image Loaded")
        pipeline.loadImage(with: Test.url, queue: queue, progress: { _, _, _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
        }, completion: { _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
            expectation.fulfill()
        })
        wait()

        // Cleanup
        waitAndDeinitPipeline()
    }

    func _testChangingCallbackQueueLoadData() {
        // Given
        let queue = DispatchQueue(label: "testChangingCallbackQueue")
        let queueKey = DispatchSpecificKey<Void>()
        queue.setSpecific(key: queueKey, value: ())

        // When/Then
        let expectation = self.expectation(description: "Image data Loaded")
        pipeline.loadData(with: Test.request,queue: queue, progress: { _, _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
        }, completion: { _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
            expectation.fulfill()
        })
        wait()

        // Cleanup
        waitAndDeinitPipeline()
    }

    // MARK: - Updating Priority

    func testDataLoadingPriorityUpdated() {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        autoreleasepool {
            let request = Test.request
            XCTAssertEqual(request.priority, .normal)

            let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

            let task = pipeline.loadImage(with: request)
            wait() // Wait till the operation is created.

            // When/Then
            guard let operation = observer.operations.first else {
                XCTFail("Failed to find operation")
                return
            }
            expect(operation).toUpdatePriority()
            task.priority = .high
            wait()
        }

        // Cleanup
        queue.isSuspended = false
        waitAndDeinitPipeline()
    }

    func testDecodingPriorityUpdated() {
        ImagePipeline.Configuration.isFastTrackDecodingEnabled = false
        defer { ImagePipeline.Configuration.isFastTrackDecodingEnabled = true }

        // Given
        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        autoreleasepool {
            let request = Test.request
            XCTAssertEqual(request.priority, .normal)

            let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

            let task = pipeline.loadImage(with: request)
            wait() // Wait till the operation is created.

            // When/Then
            guard let operation = observer.operations.first else {
                XCTFail("Failed to find operation")
                return
            }
            expect(operation).toUpdatePriority()
            task.priority = .high

            wait()
        }

        // Cleanup
        queue.isSuspended = false
        waitAndDeinitPipeline()
    }

    func testProcessingPriorityUpdated() {
        // Given
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        autoreleasepool {
            let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { $0 })])
            XCTAssertEqual(request.priority, .normal)

            let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

            let task = pipeline.loadImage(with: request)
            wait() // Wait till the operation is created.

            // When/Then
            guard let operation = observer.operations.first else {
                XCTFail("Failed to find operation")
                return
            }
            expect(operation).toUpdatePriority()
            task.priority = .high
            wait()
        }

        // Cleanup
        queue.isSuspended = false
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

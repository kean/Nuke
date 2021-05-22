// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
class FetchImageTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var imageCache: MockImageCache!
    var dataCache: MockDataCache!
    var observer: ImagePipelineObserver!
    var pipeline: ImagePipeline!
    var image: FetchImage!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        imageCache = MockImageCache()
        observer = ImagePipelineObserver()
        dataCache = MockDataCache()

        pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }

        image = FetchImage()
        image.pipeline = pipeline
    }

    func testImageLoaded() throws {
        // RECORD
        let record = expect(image.$result.dropFirst()).toPublishSingleValue()

        // WHEN
        image.load(Test.request)
        wait()

        // THEN
        let result = try XCTUnwrap(try XCTUnwrap(record.last))
        XCTAssertTrue(result.isSuccess)
        XCTAssertNotNil(image.image)
        XCTAssertNotNil(image.view)
    }

    func testIsLoadingUpdated() {
        // RECORD
        expect(image.$result.dropFirst()).toPublishSingleValue()
        let isLoading = record(image.$isLoading)

        // WHEN
        image.load(Test.request)
        wait()

        // THEN
        XCTAssertEqual(isLoading.values, [false, true, false])
    }

    func testMemoryCacheLookup() throws {
        // GIVEN
        pipeline.cache[Test.request] = Test.container

        // WHEN
        image.load(Test.request)

        // THEN image loaded synchronously
        let result = try XCTUnwrap(image.result)
        XCTAssertTrue(result.isSuccess)
        let response = try XCTUnwrap(result.value)
        XCTAssertEqual(response.cacheType, .memory)
        XCTAssertNotNil(image.image)
    }

    func testPriorityUpdated() {
        let queue = pipeline.configuration.dataCachingQueue
        queue.isSuspended = true
        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

        image.priority = .high
        image.load(Test.request)
        wait() // Wait till the operation is created.

        guard let operation = observer.operations.first else {
            return XCTFail("No operations gor registered")
        }
        XCTAssertEqual(operation.queuePriority, .high)
    }

    func testPriorityUpdatedDynamically() {
        let queue = pipeline.configuration.dataCachingQueue
        queue.isSuspended = true
        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

        image.load(Test.request)
        wait() // Wait till the operation is created.

        guard let operation = observer.operations.first else {
            return XCTFail("No operations gor registered")
        }
        expect(operation).toUpdatePriority()
        image.priority = .high
        wait()
    }

    func testPublisherImageLoaded() throws {
        // RECORD
        let record = expect(image.$result.dropFirst()).toPublishSingleValue()

        // WHEN
        image.load(pipeline.imagePublisher(with: Test.request))
        wait()

        // THEN
        let result = try XCTUnwrap(try XCTUnwrap(record.last))
        XCTAssertTrue(result.isSuccess)
        XCTAssertNotNil(image.image)
        XCTAssertNotNil(image.view)
    }

    func testPublisherIsLoadingUpdated() {
        // RECORD
        expect(image.$result.dropFirst()).toPublishSingleValue()
        let isLoading = record(image.$isLoading)

        // WHEN
        image.load(pipeline.imagePublisher(with: Test.request))
        wait()

        // THEN
        XCTAssertEqual(isLoading.values, [false, true, false])
    }

    func testPublisherMemoryCacheLookup() throws {
        // GIVEN
        pipeline.cache[Test.request] = Test.container

        // WHEN
        image.load(pipeline.imagePublisher(with: Test.request))

        // THEN image loaded synchronously
        let result = try XCTUnwrap(image.result)
        XCTAssertTrue(result.isSuccess)
        let response = try XCTUnwrap(result.value)
        XCTAssertEqual(response.cacheType, .memory)
        XCTAssertNotNil(image.image)
    }

    func testRequestCancelledWhenTargetGetsDeallocated() {
        dataLoader.isSuspended = true

        // Wrap everything in autorelease pool to make sure that imageView
        // gets deallocated immediately.
        autoreleasepool {
            // Given an image view with an associated image task
            expectNotification(ImagePipelineObserver.didStartTask, object: observer)
            image.load(pipeline.imagePublisher(with: Test.request))
            wait()

            // Expect the task to be cancelled automatically
            expectNotification(ImagePipelineObserver.didCancelTask, object: observer)

            // When the fetch image instance is deallocated
            image = nil
        }
        wait()
    }
}

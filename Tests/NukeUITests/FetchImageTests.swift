// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
import NukeTestHelpers

@testable import Nuke
@testable import NukeUI

class FetchImageTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var imageCache: MockImageCache!
    var dataCache: MockDataCache!
    var observer: ImagePipelineObserver!
    var pipeline: ImagePipeline!
    var image: FetchImage!

    @MainActor
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

    @MainActor
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
    }

    @MainActor
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

    @MainActor
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

    @MainActor
    func testPriorityUpdated() {
        let queue = pipeline.configuration.dataLoadingQueue
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

    @MainActor
    func testPriorityUpdatedDynamically() {
        let queue = pipeline.configuration.dataLoadingQueue
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

    @MainActor
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
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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

// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke
@testable import NukeUI

@MainActor
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

    func testImageLoaded() throws {
        // RECORD
        let record = expect(image.$result.dropFirst()).toPublishSingleValue()

        // When
        image.load(Test.request)
        wait()

        // Then
        let result = try XCTUnwrap(try XCTUnwrap(record.last))
        XCTAssertTrue(result.isSuccess)
        XCTAssertNotNil(image.image)
    }

    func testIsLoadingUpdated() {
        // RECORD
        expect(image.$result.dropFirst()).toPublishSingleValue()
        let isLoading = record(image.$isLoading)

        // When
        image.load(Test.request)
        wait()

        // Then
        XCTAssertEqual(isLoading.values, [false, true, false])
    }

    func testMemoryCacheLookup() throws {
        // Given
        pipeline.cache[Test.request] = Test.container

        // When
        image.load(Test.request)

        // Then image loaded synchronously
        let result = try XCTUnwrap(image.result)
        XCTAssertTrue(result.isSuccess)
        let response = try XCTUnwrap(result.value)
        XCTAssertEqual(response.cacheType, .memory)
        XCTAssertNotNil(image.image)
    }

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
}

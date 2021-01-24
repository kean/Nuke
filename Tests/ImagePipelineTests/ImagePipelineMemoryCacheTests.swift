// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

/// Test how well image pipeline interacts with memory cache.
class ImagePipelineMemoryCacheTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var cache: MockImageCache!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        cache = MockImageCache()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
        }
    }

    func testThatImageIsLoaded() {
        expect(pipeline).toLoadImage(with: Test.request)
        wait()
    }

    // MARK: Caching

    func testCacheWrite() {
        // When
        expect(pipeline).toLoadImage(with: Test.request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache[Test.request])
    }

    func testCacheRead() {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        // When
        expect(pipeline).toLoadImage(with: Test.request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
        XCTAssertNotNil(cache[Test.request])
    }

    func testCacheWriteDisabled() {
        // Given
        var request = Test.request
        request.options.memoryCacheOptions.isWriteAllowed = false

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNil(cache[Test.request])
    }

    func testCacheReadDisabled() {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        var request = Test.request
        request.options.memoryCacheOptions.isReadAllowed = false

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache[Test.request])
    }

    func testTaskCountAfterCachedLoad() {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        // When
        expect(pipeline).toLoadImage(with: Test.request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
        XCTAssertNotNil(cache[Test.request])
        XCTAssertEqual(pipeline.taskCount, 0)
    }

    func testReloadIgnoringCacheData() {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        var request = Test.request
        request.cachePolicy = .reloadIgnoringCachedData

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache[Test.request])
    }

    func testReloadRemovingCacheData() {
        // Given
        let request = Test.request
        cache[request] = ImageContainer(image: Test.image)

        // When
        pipeline.removeCachedImage(for: request)
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache[request])
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
import UIKit
#endif

class ImagePipelineProcessorTests: XCTestCase {
    var mockDataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        mockDataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = mockDataLoader
            $0.imageCache = nil
        }
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Applying Filters

    func testThatImageIsProcessed() {
        // Given
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "processor1")])

        // When
        expect(pipeline).toLoadImage(with: request) { result in
            // Then
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["processor1"])
        }
        wait()
    }

    // MARK: - Composing Filters

    func testApplyingMultipleProcessors() {
        // Given
        let request = ImageRequest(
            url: Test.url,
            processors: [
                MockImageProcessor(id: "processor1"),
                MockImageProcessor(id: "processor2")
            ]
        )

        // When
        expect(pipeline).toLoadImage(with: request) { result in
            // Then
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["processor1", "processor2"])
        }
        wait()
    }

    func testPerformingRequestWithoutProcessors() {
        // Given
        let request = ImageRequest(url: Test.url, processors: [])

        // When
        expect(pipeline).toLoadImage(with: request) { result in
            // Then
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], [])
        }
        wait()
    }
}

class ImagePipelineDefaultProcessorsTests: XCTestCase {
    var imageCache: MockImageCache!
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        imageCache = MockImageCache()
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.processors = [MockImageProcessor(id: "p1")]
        }
    }

    // MARK: ImagePipeline loadImage()

    func testDefaultProcessorsAreApplied() {
        // GIVEN
        let request = ImageRequest(url: Test.url)

        // WHEN
        expect(pipeline).toLoadImage(with: request) { result in
            // THEN
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["p1"])
        }
        wait()
    }

    func testDefaultProcessorsAppliedWhenNilPassed() {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: nil)

        // WHEN
        expect(pipeline).toLoadImage(with: request) { result in
            // THEN
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["p1"])
        }
        wait()
    }

    func testDefaultProcessorsNotAppliedWhenEmptyListPassed() {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: [])

        // WHEN
        expect(pipeline).toLoadImage(with: request) { result in
            // THEN
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], [])
        }
        wait()
    }

    func testDefautProcessorsNotAppliedWhenNonEmptyListPassed() {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p2")])

        // WHEN
        expect(pipeline).toLoadImage(with: request) { result in
            // THEN
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["p2"])
        }
        wait()
    }

    // MARK: Other Scenarios

    func testImageViewExtensionUsesDefaultProcessorForCacheLookup() {
        // GIVEN
        let view = _ImageView()
        imageCache[ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])] = Test.container

        // WHEN
        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        let task = Nuke.loadImage(with: Test.request, options: options, into: view)

        // THEN image found in memory cache
        XCTAssertNil(task)
        XCTAssertNotNil(view.image)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    func testImagePublisherUsesDefaultProcessorsForCacheLookup() {
        // GIVEN
        imageCache[ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])] = Test.container

        // WHEN
        let publisher = pipeline.imagePublisher(with: Test.url)
        var response: ImageResponse?
        _ = publisher.sink(receiveCompletion: { _ in }, receiveValue: {
            response = $0
        })

        // THEN image found in memory cache
        XCTAssertNotNil(response)
    }

    func testImagePipelineCacheDoesntUseDefaultProcessorForCacheLookup() {
        // GIVEN
        let cachedRequest = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
        imageCache[cachedRequest] = Test.container

        // WHEN
        let cachedImage = pipeline.cache[Test.url]

        // THEN
        XCTAssertNil(cachedImage?.image)
    }
}

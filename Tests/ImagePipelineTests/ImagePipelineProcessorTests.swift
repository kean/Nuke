// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

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

    func testImageIsProcessedWithDefaultProcessors() {
        // Given
        pipeline = ImagePipeline {
            $0.dataLoader = mockDataLoader
            $0.processors = [MockImageProcessor(id: "processor1")]
        }
        let request = ImageRequest(url: Test.url)

        // When
        expect(pipeline).toLoadImage(with: request) { result in
            // Then
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["processor1"])
        }
        wait()
    }

    func testItAppliesImageRequestOwnProcessors() {
        // Given
        pipeline = ImagePipeline {
            $0.dataLoader = mockDataLoader
            $0.processors = [MockImageProcessor(id: "processor1")]
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "processor2")])

        // When
        expect(pipeline).toLoadImage(with: request) { result in
            // Then
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["processor2"])
        }
        wait()
    }

    func testItProcessesCacheLookups() {
        // Given
        let mockProcessor = MockImageProcessor(id: "processor1")
        let mockImageCache = MockImageCache()
        pipeline = ImagePipeline {
            $0.dataLoader = mockDataLoader
            $0.processors = [mockProcessor]
            $0.imageCache = mockImageCache
        }

        let underlyingRequest = ImageRequest(url: Test.url, processors: [mockProcessor])
        let image = Test.image
        mockImageCache[underlyingRequest] = ImageContainer(image: image)

        // When
        let container = pipeline.cachedImage(for: ImageRequest(url: Test.url))

        // Then
        XCTAssertEqual(container?.image, image)
    }
}

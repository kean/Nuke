// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

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
    }

    override func tearDown() {
        super.tearDown()
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
        mockImageCache.storeResponse(Test.response, for: underlyingRequest)

        // When
        let response = pipeline.cachedResponse(for: ImageRequest(url: Test.url))

        // Then
        XCTAssertEqual(response?.image, Test.response.image)
    }
}

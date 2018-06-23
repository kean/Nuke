// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

class ImageProcessingTests: XCTestCase {
    var mockDataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        mockDataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = mockDataLoader
            return // !swift(>=4.1)
        }
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Applying Filters

    func testThatImageIsProcessed() {
        // Given
        let request = Test.request.processed(with: MockImageProcessor(id: "processor1"))

        // When
        expect(pipeline).toLoadImage(with: request) { response, _ in
            // Then
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["processor1"])
        }
        wait()
    }

    // MARK: - Composing Filters

    func testApplyingMultipleProcessors() {
        // Given
        let request = Test.request
            .processed(with: MockImageProcessor(id: "processor1"))
            .processed(with: MockImageProcessor(id: "processor2"))

        // When
        expect(pipeline).toLoadImage(with: request) { response, _ in
            // Then
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], ["processor1", "processor2"])
        }
        wait()
    }

    func testPerformingRequestWithoutProcessors() {
        // Given
        var request = Test.request
        request.processor = nil

        // When
        expect(pipeline).toLoadImage(with: request) { response, _ in
            // Then
            XCTAssertEqual(response?.image.nk_test_processorIDs ?? [], [])
        }
        wait()
    }

    // MARK: - Anonymous Processor

    func testAnonymousProcessorsEquatable() {
        XCTAssertEqual(
            Test.request.processed(key: 1, { $0 }).processor,
            Test.request.processed(key: 1, { $0 }).processor
        )
        XCTAssertNotEqual(
            Test.request.processed(key: 1, { $0 }).processor,
            Test.request.processed(key: 2, { $0 }).processor
        )
    }

    func testAnonymousProcessorIsApplied() {
        // Given
        let request = Test.request.processed(key: 1) {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)

        // When
        let image = request.processor?.process(image: Image(), context: context)

        // Then
        XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["1"])
    }

    func testAnonymousProcessorIsApplied2() {
        // Given
        var request = Test.request
        request.process(key: 1) {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)

        // When
        let image = request.processor?.process(image: Image(), context: context)

        // Then
        XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["1"])
    }

    // MARK: - Resizing

    #if !os(macOS)
    func testResizingUsingRequestParameters() {
        // Given
        let request = ImageRequest(url: Test.url, targetSize: CGSize(width: 40, height: 40), contentMode: .aspectFit)
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)

        // When
        let image = request.processor!.process(image: Test.image, context: context)

        // Then
        XCTAssertEqual(image?.cgImage?.width, 40)
        XCTAssertEqual(image?.cgImage?.height, 30)
    }
    #endif
}

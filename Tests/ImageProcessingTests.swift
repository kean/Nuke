// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

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
            return
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
        expect(pipeline).toLoadImage(with: request) { result in
            // Then
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["processor1"])
        }
        wait()
    }

    func testReplacingDefaultProcessor() {
        // Given
        var request = Test.request
        request.processor = nil
        request.process(with: MockImageProcessor(id: "processor1"))

        // When
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
        let request = Test.request
            .processed(with: MockImageProcessor(id: "processor1"))
            .processed(with: MockImageProcessor(id: "processor2"))

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
        var request = Test.request
        request.processor = nil

        // When
        expect(pipeline).toLoadImage(with: request) { result in
            // Then
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], [])
        }
        wait()
    }

    // MARK: - Anonymous Processor

    func testAnonymousProcessorsHaveDifferentIdentifiers() {
        XCTAssertEqual(
            Test.request.processed(key: "1", { $0 }).processor?.identifier,
            Test.request.processed(key: "1", { $0 }).processor?.identifier
        )
        XCTAssertNotEqual(
            Test.request.processed(key: "1", { $0 }).processor?.identifier,
            Test.request.processed(key: "2", { $0 }).processor?.identifier
        )
    }

    func testAnonymousProcessorsHaveDifferentHashableIdentifiers() {
        XCTAssertEqual(
            Test.request.processed(key: "1", { $0 }).processor?.hashableIdentifier,
            Test.request.processed(key: "1", { $0 }).processor?.hashableIdentifier
        )
        XCTAssertNotEqual(
            Test.request.processed(key: "1", { $0 }).processor?.hashableIdentifier,
            Test.request.processed(key: "2", { $0 }).processor?.hashableIdentifier
        )
    }

    func testAnonymousProcessorIsApplied() {
        // Given
        let request = Test.request.processed(key: "1") {
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
        request.process(key: "1") {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)

        // When
        let image = request.processor?.process(image: Image(), context: context)

        // Then
        XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["1"])
    }

    #if !os(macOS)

    // MARK: - Decompression

    func testTwoDifferentDecompressorsAreEqual() {
        XCTAssertEqual(ImageDecompression().hashValue, ImageDecompression().hashValue)
        XCTAssertEqual(ImageDecompression(), ImageDecompression())
    }

    // MARK: - Resizing

    func testUsingProcessorRequestParameter() {
        // Given
        let processor = ImageScalingProcessor(targetSize: CGSize(width: 40, height: 40), contentMode: .aspectFit, upscale: false)

        // When
        let request = ImageRequest(url: Test.url, processor: processor)

        // Then
        XCTAssertEqual(processor.identifier, request.processor?.identifier)
    }

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

    func testResizingUsingRequestParametersInitWithURLRequest() {
        // Given
        let request = ImageRequest(urlRequest: Test.request.urlRequest, targetSize: CGSize(width: 40, height: 40), contentMode: .aspectFit)
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)

        // When
        let image = request.processor!.process(image: Test.image, context: context)

        // Then
        XCTAssertEqual(image?.cgImage?.width, 40)
        XCTAssertEqual(image?.cgImage?.height, 30)
    }

    func testResizingShouldNotUpscaleWithoutParamater() {
        // Given
        let targetSize = CGSize(width: 960, height: 720)
        let request = ImageRequest(url: Test.url, targetSize: targetSize, contentMode: .aspectFit)
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)

        // When
        let image = request.processor!.process(image: Test.image, context: context)

        // Then
        XCTAssertEqual(image?.cgImage?.width, 640)
        XCTAssertEqual(image?.cgImage?.height, 480)
    }

    func testResizingShouldUpscaleWithParamater() {
        // Given
        let targetSize = CGSize(width: 960, height: 720)
        let request = ImageRequest(url: Test.url, targetSize: targetSize, contentMode: .aspectFit, upscale: true)
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)

        // When
        let image = request.processor!.process(image: Test.image, context: context)

        // Then
        XCTAssertEqual(image?.cgImage?.width, 960)
        XCTAssertEqual(image?.cgImage?.height, 720)
    }
    #endif
}

class ImageProcessorCompositionTest: XCTestCase {

    func testAppliesAllProcessors() {
        // Given
        let processor = ImageProcessorComposition([
            MockImageProcessor(id: "1"),
            MockImageProcessor(id: "2")]
        )

        // When
        let image = processor.process(image: Image(), context: dummyProcessingContext)

        // Then
        XCTAssertEqual(image?.nk_test_processorIDs, ["1", "2"])
    }

    func testIdenfitiers() {
        // Given different processors
        let lhs = ImageProcessorComposition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessorComposition([MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdentifiersDifferentProcessorCount() {
        // Given processors with different processor count
        let lhs = ImageProcessorComposition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessorComposition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdenfitiersEqualProcessors() {
        // Given processors with equal processors
        let lhs = ImageProcessorComposition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])
        let rhs = ImageProcessorComposition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertEqual(lhs.identifier, rhs.identifier)
        XCTAssertEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdentifiersWithSameProcessorsButInDifferentOrder() {
        // Given processors with equal processors but in different order
        let lhs = ImageProcessorComposition([MockImageProcessor(id: "2"), MockImageProcessor(id: "1")])
        let rhs = ImageProcessorComposition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdenfitiersEmptyProcessors() {
        // Given empty processors
        let lhs = ImageProcessorComposition([])
        let rhs = ImageProcessorComposition([])

        // Then
        XCTAssertEqual(lhs.identifier, rhs.identifier)
        XCTAssertEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }
}

private let dummyProcessingContext = ImageProcessingContext(request: Test.request, isFinal: true, scanNumber: nil)

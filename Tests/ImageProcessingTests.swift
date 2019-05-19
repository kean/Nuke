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

    // MARK: - Anonymous Processor

    func testAnonymousProcessorsHaveDifferentIdentifiers() {
        XCTAssertEqual(
            ImageProcessor.Anonymous("1", { $0 }).identifier,
            ImageProcessor.Anonymous("1", { $0 }).identifier
        )
        XCTAssertNotEqual(
            ImageProcessor.Anonymous("1", { $0 }).identifier,
            ImageProcessor.Anonymous("2", { $0 }).identifier
        )
    }

    func testAnonymousProcessorsHaveDifferentHashableIdentifiers() {
        XCTAssertEqual(
            ImageProcessor.Anonymous("1", { $0 }).hashableIdentifier,
            ImageProcessor.Anonymous("1", { $0 }).hashableIdentifier
        )
        XCTAssertNotEqual(
            ImageProcessor.Anonymous("1", { $0 }).hashableIdentifier,
            ImageProcessor.Anonymous("2", { $0 }).hashableIdentifier
        )
    }

    func testAnonymousProcessorIsApplied() {
        // Given
        let processor = ImageProcessor.Anonymous("1") {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }
        let request = ImageRequest(url: Test.url, processors: [processor])

        // When
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)
        let image = processor.process(image: Test.image, context: context)

        // Then
        XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["1"])
    }

    #if !os(macOS)

    // MARK: - Decompression

    func testTwoDifferentDecompressorsAreEqual() {
        XCTAssertEqual(ImageDecompressor().hashValue, ImageDecompressor().hashValue)
        XCTAssertEqual(ImageDecompressor(), ImageDecompressor())
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

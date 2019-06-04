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
}

// MARK: - ImageProcessorResizeTests

class ImageProcessorResizeTests: XCTestCase {

    func testThatImageIsResizedToFill() {
        // Given
        let processor = ImageProcessor.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)

        // When
        guard let image = processor.process(image: Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 533)
        XCTAssertEqual(cgImage.height, 400)
    }

    func testThatImageIsntUpscaledByDefault() {
        // Given
        let processor = ImageProcessor.Resize(size: CGSize(width: 960, height: 960), unit: .pixels, contentMode: .aspectFill)

        // When
        guard let image = processor.process(image: Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 640)
        XCTAssertEqual(cgImage.height, 480)
    }

    func testThatImageIsUpscaledIfOptionIsEnabled() {
        // Given
        let processor = ImageProcessor.Resize(size: CGSize(width: 960, height: 960), unit: .pixels, contentMode: .aspectFill, upscale: true)

        // When
        guard let image = processor.process(image: Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 1280)
        XCTAssertEqual(cgImage.height, 960)
    }

    func testThatContentModeCanBeChangeToAspectFit() {
        // Given
        let processor = ImageProcessor.Resize(size: CGSize(width: 480, height: 480), unit: .pixels, contentMode: .aspectFit)

        // When
        guard let image = processor.process(image: Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 480)
        XCTAssertEqual(cgImage.height, 360)
    }

    func testThatImageIsCropped() {
        // Given
        let processor = ImageProcessor.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, crop: true)

        // When
        guard let image = processor.process(image: Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 400)
        XCTAssertEqual(cgImage.height, 400)
    }

    #if os(iOS) || os(tvOS)
    func testThatScalePreserved() {
        // Given
        let processor = ImageProcessor.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)

        // When
        guard let image = processor.process(image: Test.image) else {
            return XCTFail("Fail to process the image")
        }

        // Then
        XCTAssertEqual(image.scale, Test.image.scale)
    }
    #endif
}

// MARK: - ImageProcessorCircleTests

#if os(iOS) || os(tvOS)
class ImageProcessorCircleTests: XCTestCase {

    func testThatImageIsCroppedToSquareAutomatically() {
        // Given
        let processor = ImageProcessor.Circle()

        // When
        guard let image = processor.process(image: Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 480)
        XCTAssertEqual(cgImage.height, 480)
    }
}
#endif

// MARK: - ImageProcessorRoundedCornersTests

#if os(iOS) || os(tvOS)
class ImageProcessorRoundedCornersTests: XCTestCase {

    /// We don't check the actual output yet, just that it compiles and that
    /// _some_ output is produced.
    func testThatImageIsProduced() {
        // Given
        let processor = ImageProcessor.RoundedCorners(radius: 12)

        // When
        guard let image = processor.process(image: Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 640)
        XCTAssertEqual(cgImage.height, 480)
    }
}
#endif

// MARK: - ImageProcessorAnonymousTests

class ImageProcessorAnonymousTests: XCTestCase {

    func testAnonymousProcessorsHaveDifferentIdentifiers() {
        XCTAssertEqual(
            ImageProcessor.Anonymous(id: "1", { $0 }).identifier,
            ImageProcessor.Anonymous(id: "1", { $0 }).identifier
        )
        XCTAssertNotEqual(
            ImageProcessor.Anonymous(id: "1", { $0 }).identifier,
            ImageProcessor.Anonymous(id: "2", { $0 }).identifier
        )
    }

    func testAnonymousProcessorsHaveDifferentHashableIdentifiers() {
        XCTAssertEqual(
            ImageProcessor.Anonymous(id: "1", { $0 }).hashableIdentifier,
            ImageProcessor.Anonymous(id: "1", { $0 }).hashableIdentifier
        )
        XCTAssertNotEqual(
            ImageProcessor.Anonymous(id: "1", { $0 }).hashableIdentifier,
            ImageProcessor.Anonymous(id: "2", { $0 }).hashableIdentifier
        )
    }

    func testAnonymousProcessorIsApplied() {
        // Given
        let processor = ImageProcessor.Anonymous(id: "1") {
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
}

// MARK: - ImageProcessorCompositionTest

class ImageProcessorCompositionTest: XCTestCase {

    func testAppliesAllProcessors() {
        // Given
        let processor = ImageProcessor.Composition([
            MockImageProcessor(id: "1"),
            MockImageProcessor(id: "2")]
        )

        // When
        let image = processor.process(image: Test.image)

        // Then
        XCTAssertEqual(image?.nk_test_processorIDs, ["1", "2"])
    }

    func testIdenfitiers() {
        // Given different processors
        let lhs = ImageProcessor.Composition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessor.Composition([MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs, rhs)
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdentifiersDifferentProcessorCount() {
        // Given processors with different processor count
        let lhs = ImageProcessor.Composition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessor.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs, rhs)
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdenfitiersEqualProcessors() {
        // Given processors with equal processors
        let lhs = ImageProcessor.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])
        let rhs = ImageProcessor.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        XCTAssertEqual(lhs.identifier, rhs.identifier)
        XCTAssertEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdentifiersWithSameProcessorsButInDifferentOrder() {
        // Given processors with equal processors but in different order
        let lhs = ImageProcessor.Composition([MockImageProcessor(id: "2"), MockImageProcessor(id: "1")])
        let rhs = ImageProcessor.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs, rhs)
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdenfitiersEmptyProcessors() {
        // Given empty processors
        let lhs = ImageProcessor.Composition([])
        let rhs = ImageProcessor.Composition([])

        // Then
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        XCTAssertEqual(lhs.identifier, rhs.identifier)
        XCTAssertEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testThatIdentifiesAreFlattened() {
        let lhs = ImageProcessor.Composition([
            ImageProcessor.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")]),
            ImageProcessor.Composition([MockImageProcessor(id: "3"), MockImageProcessor(id: "4")])]
        )
        let rhs = ImageProcessor.Composition([
            MockImageProcessor(id: "1"), MockImageProcessor(id: "2"),
            MockImageProcessor(id: "3"), MockImageProcessor(id: "4")]
        )

        // Then
        XCTAssertEqual(lhs.identifier, rhs.identifier)
    }
}

// MARK: - CoreGraphics Extensions Tests (Internal)

class CoreGraphicsExtensionsTests: XCTestCase {
    func testScaleToFill() {
        XCTAssertEqual(1, CGSize(width: 10, height: 10).scaleToFill(CGSize(width: 10, height: 10)))
        XCTAssertEqual(0.5, CGSize(width: 20, height: 20).scaleToFill(CGSize(width: 10, height: 10)))
        XCTAssertEqual(2, CGSize(width: 5, height: 5).scaleToFill(CGSize(width: 10, height: 10)))

        XCTAssertEqual(1, CGSize(width: 20, height: 10).scaleToFill(CGSize(width: 10, height: 10)))
        XCTAssertEqual(1, CGSize(width: 10, height: 20).scaleToFill(CGSize(width: 10, height: 10)))
        XCTAssertEqual(0.5, CGSize(width: 30, height: 20).scaleToFill(CGSize(width: 10, height: 10)))
        XCTAssertEqual(0.5, CGSize(width: 20, height: 30).scaleToFill(CGSize(width: 10, height: 10)))

        XCTAssertEqual(2, CGSize(width: 5, height: 10).scaleToFill(CGSize(width: 10, height: 10)))
        XCTAssertEqual(2, CGSize(width: 10, height: 5).scaleToFill(CGSize(width: 10, height: 10)))
        XCTAssertEqual(2, CGSize(width: 5, height: 8).scaleToFill(CGSize(width: 10, height: 10)))
        XCTAssertEqual(2, CGSize(width: 8, height: 5).scaleToFill(CGSize(width: 10, height: 10)))

        XCTAssertEqual(2, CGSize(width: 30, height: 10).scaleToFill(CGSize(width: 10, height: 20)))
        XCTAssertEqual(2, CGSize(width: 10, height: 30).scaleToFill(CGSize(width: 20, height: 10)))
    }

    func testScaleToFit() {
        XCTAssertEqual(1, CGSize(width: 10, height: 10).scaleToFit(CGSize(width: 10, height: 10)))
        XCTAssertEqual(0.5, CGSize(width: 20, height: 20).scaleToFit(CGSize(width: 10, height: 10)))
        XCTAssertEqual(2, CGSize(width: 5, height: 5).scaleToFit(CGSize(width: 10, height: 10)))

        XCTAssertEqual(0.5, CGSize(width: 20, height: 10).scaleToFit(CGSize(width: 10, height: 10)))
        XCTAssertEqual(0.5, CGSize(width: 10, height: 20).scaleToFit(CGSize(width: 10, height: 10)))
        XCTAssertEqual(0.25, CGSize(width: 40, height: 20).scaleToFit(CGSize(width: 10, height: 10)))
        XCTAssertEqual(0.25, CGSize(width: 20, height: 40).scaleToFit(CGSize(width: 10, height: 10)))

        XCTAssertEqual(1, CGSize(width: 5, height: 10).scaleToFit(CGSize(width: 10, height: 10)))
        XCTAssertEqual(1, CGSize(width: 10, height: 5).scaleToFit(CGSize(width: 10, height: 10)))
        XCTAssertEqual(2, CGSize(width: 2, height: 5).scaleToFit(CGSize(width: 10, height: 10)))
        XCTAssertEqual(2, CGSize(width: 5, height: 2).scaleToFit(CGSize(width: 10, height: 10)))

        XCTAssertEqual(0.25, CGSize(width: 40, height: 10).scaleToFit(CGSize(width: 10, height: 20)))
        XCTAssertEqual(0.25, CGSize(width: 10, height: 40).scaleToFit(CGSize(width: 20, height: 10)))
    }

    func testCenteredInRectWithSize() {
        XCTAssertEqual(
            CGSize(width: 10, height: 10).centeredInRectWithSize(CGSize(width: 10, height: 10)),
            CGRect(x: 0, y: 0, width: 10, height: 10)
        )
        XCTAssertEqual(
            CGSize(width: 20, height: 20).centeredInRectWithSize(CGSize(width: 10, height: 10)),
            CGRect(x: -5, y: -5, width: 20, height: 20)
        )
        XCTAssertEqual(
            CGSize(width: 20, height: 10).centeredInRectWithSize(CGSize(width: 10, height: 10)),
            CGRect(x: -5, y: 0, width: 20, height: 10)
        )
        XCTAssertEqual(
            CGSize(width: 10, height: 20).centeredInRectWithSize(CGSize(width: 10, height: 10)),
            CGRect(x: 0, y: -5, width: 10, height: 20)
        )
        XCTAssertEqual(
            CGSize(width: 10, height: 20).centeredInRectWithSize(CGSize(width: 10, height: 20)),
            CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        XCTAssertEqual(
            CGSize(width: 10, height: 40).centeredInRectWithSize(CGSize(width: 10, height: 20)),
            CGRect(x: 0, y: -10, width: 10, height: 40)
        )
    }
}

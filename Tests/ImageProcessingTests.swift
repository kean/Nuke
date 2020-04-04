// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

// MARK: - ImageProcessors.Resize

class ImageProcessorResizeTests: XCTestCase {

    func testThatImageIsResizedToFill() {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)

        // When
        guard let image = processor.process(Test.image) else {
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
        let processor = ImageProcessors.Resize(size: CGSize(width: 960, height: 960), unit: .pixels, contentMode: .aspectFill)

        // When
        guard let image = processor.process(Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 640)
        XCTAssertEqual(cgImage.height, 480)
    }

    func testResizeToFitHeight() {
        // Given
        let processor = ImageProcessors.Resize(height: 300, unit: .pixels)

        // When
        guard let image = processor.process(Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 400)
        XCTAssertEqual(cgImage.height, 300)
    }

    func testResizeToFitWidth() {
        // Given
        let processor = ImageProcessors.Resize(width: 400, unit: .pixels)

        // When
        guard let image = processor.process(Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 400)
        XCTAssertEqual(cgImage.height, 300)
    }

    func testThatImageIsUpscaledIfOptionIsEnabled() {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 960, height: 960), unit: .pixels, contentMode: .aspectFill, upscale: true)

        // When
        guard let image = processor.process(Test.image) else {
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
        let processor = ImageProcessors.Resize(size: CGSize(width: 480, height: 480), unit: .pixels, contentMode: .aspectFit)

        // When
        guard let image = processor.process(Test.image) else {
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
        let processor = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, crop: true)

        // When
        guard let image = processor.process(Test.image) else {
            return XCTFail("Fail to process the image")
        }
        guard let cgImage = image.cgImage else {
            return XCTFail("Expected to have CGImage backing the image")
        }

        // Then
        XCTAssertEqual(cgImage.width, 400)
        XCTAssertEqual(cgImage.height, 400)
    }

    func testThatImageIsntCroppedWithAspectFitMode() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 480, height: 480), unit: .pixels, contentMode: .aspectFit, crop: true)

        // When
        let image = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")
        let cgImage = try XCTUnwrap(image.cgImage, "Expected image to be backed by CGImage")

        // Then image is resized but isn't cropped
        XCTAssertEqual(cgImage.width, 480)
        XCTAssertEqual(cgImage.height, 360)
    }

    #if os(iOS) || os(tvOS)
    func testThatScalePreserved() {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)

        // When
        guard let image = processor.process(Test.image) else {
            return XCTFail("Fail to process the image")
        }

        // Then
        XCTAssertEqual(image.scale, Test.image.scale)
    }
    #endif

    func testThatIdentifiersAreEqualWithSameParameters() {
        XCTAssertEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).identifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).identifier
        )
        XCTAssertEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).identifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).identifier
        )
        XCTAssertEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).identifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).identifier
        )
        XCTAssertEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).identifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).identifier
        )
    }

    func testThatIdentifiersAreNotEqualWithDifferentParameters() {
        XCTAssertNotEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).identifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 40)).identifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).identifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: false).identifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).identifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: false).identifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).identifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFill).identifier
        )
    }

    func testThatHashableIdentifiersAreEqualWithSameParameters() {
        XCTAssertEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).hashableIdentifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).hashableIdentifier
        )
        XCTAssertEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).hashableIdentifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).hashableIdentifier
        )
        XCTAssertEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).hashableIdentifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).hashableIdentifier
        )
        XCTAssertEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).hashableIdentifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).hashableIdentifier
        )
    }

    func testThatHashableIdentifiersAreNotEqualWithDifferentParameters() {
        XCTAssertNotEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).hashableIdentifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 40)).hashableIdentifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).hashableIdentifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: false).hashableIdentifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).hashableIdentifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: false).hashableIdentifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).hashableIdentifier,
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFill).hashableIdentifier
        )
    }

    func testDesscription() {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit)

        // Then
        XCTAssertEqual(processor.description, "Resize(size in points: (30.0, 30.0), contentMode: .aspectFit, crop: false, upscale: false)")
    }
}

// MARK: - ImageProcessors.Circle

#if os(iOS) || os(tvOS)
class ImageProcessorCircleTests: XCTestCase {

    func testThatImageIsCroppedToSquareAutomatically() {
        // Given
        let processor = ImageProcessors.Circle()

        // When
        guard let image = processor.process(Test.image) else {
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

// MARK: - ImageProcessors.RoundedCorners

#if os(iOS) || os(tvOS)
class ImageProcessorRoundedCornersTests: XCTestCase {

    /// We don't check the actual output yet, just that it compiles and that
    /// _some_ output is produced.
    func testThatImageIsProduced() {
        // Given
        let processor = ImageProcessors.RoundedCorners(radius: 12)

        // When
        guard let image = processor.process(Test.image) else {
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

// MARK: - ImageProcessors.Anonymous

class ImageProcessorAnonymousTests: XCTestCase {

    func testAnonymousProcessorsHaveDifferentIdentifiers() {
        XCTAssertEqual(
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier,
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Anonymous(id: "1", { $0 }).identifier,
            ImageProcessors.Anonymous(id: "2", { $0 }).identifier
        )
    }

    func testAnonymousProcessorsHaveDifferentHashableIdentifiers() {
        XCTAssertEqual(
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier,
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Anonymous(id: "1", { $0 }).hashableIdentifier,
            ImageProcessors.Anonymous(id: "2", { $0 }).hashableIdentifier
        )
    }

    func testAnonymousProcessorIsApplied() {
        // Given
        let processor = ImageProcessors.Anonymous(id: "1") {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }

        // When
        let image = processor.process(Test.image)

        // Then
        XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["1"])
    }
}

// MARK: - ImageProcessors.Composition

class ImageProcessorCompositionTest: XCTestCase {

    func testAppliesAllProcessors() {
        // Given
        let processor = ImageProcessors.Composition([
            MockImageProcessor(id: "1"),
            MockImageProcessor(id: "2")]
        )

        // When
        let image = processor.process(Test.image)

        // Then
        XCTAssertEqual(image?.nk_test_processorIDs, ["1", "2"])
    }

    func testIdenfitiers() {
        // Given different processors
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs, rhs)
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdentifiersDifferentProcessorCount() {
        // Given processors with different processor count
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs, rhs)
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdenfitiersEqualProcessors() {
        // Given processors with equal processors
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        XCTAssertEqual(lhs.identifier, rhs.identifier)
        XCTAssertEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdentifiersWithSameProcessorsButInDifferentOrder() {
        // Given processors with equal processors but in different order
        let lhs = ImageProcessors.Composition([MockImageProcessor(id: "2"), MockImageProcessor(id: "1")])
        let rhs = ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")])

        // Then
        XCTAssertNotEqual(lhs, rhs)
        XCTAssertNotEqual(lhs.identifier, rhs.identifier)
        XCTAssertNotEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testIdenfitiersEmptyProcessors() {
        // Given empty processors
        let lhs = ImageProcessors.Composition([])
        let rhs = ImageProcessors.Composition([])

        // Then
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        XCTAssertEqual(lhs.identifier, rhs.identifier)
        XCTAssertEqual(lhs.hashableIdentifier, rhs.hashableIdentifier)
    }

    func testThatIdentifiesAreFlattened() {
        let lhs = ImageProcessors.Composition([
            ImageProcessors.Composition([MockImageProcessor(id: "1"), MockImageProcessor(id: "2")]),
            ImageProcessors.Composition([MockImageProcessor(id: "3"), MockImageProcessor(id: "4")])]
        )
        let rhs = ImageProcessors.Composition([
            MockImageProcessor(id: "1"), MockImageProcessor(id: "2"),
            MockImageProcessor(id: "3"), MockImageProcessor(id: "4")]
        )

        // Then
        XCTAssertEqual(lhs.identifier, rhs.identifier)
    }
}

#if os(iOS) || os(tvOS)

// MARK: - ImageProcessors.GaussianBlur

class ImageProcessorGaussianBlurTest: XCTestCase {
    func testApplyBlur() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()
        XCTAssertFalse(processor.description.isEmpty) // Bumping that test coverage

        // When
        let processed = processor.process(image)

        // Then
        XCTAssertNotNil(processed)
    }

    func testApplyBlurProducesImagesBackedByCoreGraphics() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        let processed = processor.process(image)

        // Then
        XCTAssertNotNil(processed?.cgImage)
    }

    func testApplyBlurProducesTransparentImages() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        let processed = processor.process(image)

        // Then
        XCTAssertEqual(processed?.cgImage?.isOpaque, false)
    }

    func testImagesWithSameRadiusHasSameIdentifiers() {
        XCTAssertEqual(
            ImageProcessors.GaussianBlur(radius: 2).identifier,
            ImageProcessors.GaussianBlur(radius: 2).identifier
        )
    }

    func testImagesWithDifferentRadiusHasDifferentIdentifiers() {
        XCTAssertNotEqual(
            ImageProcessors.GaussianBlur(radius: 2).identifier,
            ImageProcessors.GaussianBlur(radius: 3).identifier
        )
    }

    func testImagesWithSameRadiusHasSameHashableIdentifiers() {
        XCTAssertEqual(
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier,
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier
        )
    }

    func testImagesWithDifferentRadiusHasDifferentHashableIdentifiers() {
        XCTAssertNotEqual(
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier,
            ImageProcessors.GaussianBlur(radius: 3).hashableIdentifier
        )
    }
}

#endif

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

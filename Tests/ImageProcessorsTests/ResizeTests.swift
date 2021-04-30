// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

class ImageProcessorsResizeTests: XCTestCase {

    func testThatImageIsResizedToFill() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)

        // When
        let output = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 533, height: 400))
    }

    func testThatImageIsntUpscaledByDefault() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 960, height: 960), unit: .pixels, contentMode: .aspectFill)

        // When
        let output = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 640, height: 480))
    }

    func testResizeToFitHeight() throws {
        // Given
        let processor = ImageProcessors.Resize(height: 300, unit: .pixels)

        // When
        let output = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 400, height: 300))
    }

    func testResizeToFitWidth() throws {
        // Given
        let processor = ImageProcessors.Resize(width: 400, unit: .pixels)

        // When
        let output = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 400, height: 300))
    }

    func testThatImageIsUpscaledIfOptionIsEnabled() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 960, height: 960), unit: .pixels, contentMode: .aspectFill, upscale: true)

        // When
        let output = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 1280, height: 960))
    }

    func testThatContentModeCanBeChangeToAspectFit() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 480, height: 480), unit: .pixels, contentMode: .aspectFit)

        // When
        let output = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 480, height: 360))
    }

    func testThatImageIsCropped() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, crop: true)

        // When
        let output = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 400, height: 400))
    }

    func testThatImageIsntCroppedWithAspectFitMode() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 480, height: 480), unit: .pixels, contentMode: .aspectFit, crop: true)

        // When
        let output = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")

        // Then image is resized but isn't cropped
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 480, height: 360))
    }

    func testExtendedColorSpaceSupport() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 480, height: 480), unit: .pixels, contentMode: .aspectFit, crop: true)

        // When
        let output = try XCTUnwrap(processor.process(Test.image(named: "image-p3", extension: "jpg")), "Failed to process an image")

        // Then image is resized but isn't cropped
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 480, height: 320))
        let colorSpace = try XCTUnwrap(output.cgImage?.colorSpace)
        XCTAssertTrue(colorSpace.isWideGamutRGB)
    }

    #if os(macOS)
    func testResizeImageWithOrientationLeft() throws {
        // Given an image with `left` orientation. From the user perspective,
        // the image a landscape image with s size 640x480px. The raw pixel
        // data, on the other hand, is 480x640px. macOS, however, automatically
        // changes image orientaiton to `up` so that you don't have to worry about it
        let input = try XCTUnwrap(Test.image(named: "left-orientation.jpeg"))

        // When we resize the image to fit 320x480px frame, we expect the processor
        // to take image orientation into the account and produce a 320x240px.
        let processor = ImageProcessors.Resize(size: CGSize(width: 320, height: 1000), unit: .pixels, contentMode: .aspectFit)
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then the image orientation is still `.left`
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 320, height: 240))

        // Then the image is resized according to orientation
        XCTAssertEqual(output.size, CGSize(width: 320 / Screen.scale, height: 240 / Screen.scale))
    }
    #endif

    #if os(iOS) || os(tvOS) || os(watchOS)
    func testResizeImageWithOrientationLeft() throws {
        // Given an image with `right` orientation. From the user perspective,
        // the image a landscape image with s size 640x480px. The raw pixel
        // data, on the other hand, is 480x640px.
        let input = try XCTUnwrap(Test.image(named: "left-orientation.jpeg"))
        XCTAssertEqual(input.imageOrientation, .right)

        // When we resize the image to fit 320x480px frame, we expect the processor
        // to take image orientation into the account and produce a 320x240px.
        let processor = ImageProcessors.Resize(size: CGSize(width: 320, height: 1000), unit: .pixels, contentMode: .aspectFit)
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then the image orientation is still `.right`
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 240, height: 320))
        XCTAssertEqual(output.imageOrientation, .right)
        // Then the image is resized according to orientation
        XCTAssertEqual(output.size, CGSize(width: 320 / Screen.scale, height: 240 / Screen.scale))
    }

    func testResizeAndCropWithOrientationLeft() throws {
        // Given an image with `right` orientation. From the user perspective,
        // the image a landscape image with s size 640x480px. The raw pixel
        // data, on the other hand, is 480x640px.
        let input = try XCTUnwrap(Test.image(named: "left-orientation.jpeg"))
        XCTAssertEqual(input.imageOrientation, .right)

        // When
        let processor = ImageProcessors.Resize(size: CGSize(width: 320, height: 80), unit: .pixels, contentMode: .aspectFill, crop: true)
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 80, height: 320))
        XCTAssertEqual(output.imageOrientation, .right)
        // Then
        XCTAssertEqual(output.size, CGSize(width: 320 / Screen.scale, height: 80 / Screen.scale))
    }
    #endif

    #if os(macOS)

    #endif

    #if os(iOS) || os(tvOS)
    func testThatScalePreserved() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)

        // When
        let image = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")

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
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), unit: .pixels).identifier,
            ImageProcessors.Resize(size: CGSize(width: 30 / Screen.scale, height: 30 / Screen.scale), unit: .points).identifier
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
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), unit: .pixels).hashableIdentifier,
            ImageProcessors.Resize(size: CGSize(width: 30 / Screen.scale, height: 30 / Screen.scale), unit: .points).hashableIdentifier
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

    func testDescription() {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 30, height: 30), unit: .pixels, contentMode: .aspectFit)

        // Then
        XCTAssertEqual(processor.description, "Resize(size: (30.0, 30.0) pixels, contentMode: .aspectFit, crop: false, upscale: false)")
    }

    // Just make sure these initailizers are still available.
    func testInitailizer() {
        _ = ImageProcessors.Resize(height: 10)
        _ = ImageProcessors.Resize(width: 10)
        _ = ImageProcessors.Resize(width: 10, upscale: true)
        _ = ImageProcessors.Resize(width: 10, unit: .pixels, upscale: true)
    }
}

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

private extension CGSize {
    func scaleToFill(_ targetSize: CGSize) -> CGFloat {
        getScale(targetSize: targetSize, contentMode: .aspectFill)
    }

    func scaleToFit(_ targetSize: CGSize) -> CGFloat {
        getScale(targetSize: targetSize, contentMode: .aspectFit)
    }
}

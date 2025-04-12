// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@Suite struct ImageProcessorsResizeTests {

    @Test func thatImageIsResizedToFill() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)

        // When
        let output = try #require(processor.process(Test.image), "Failed to process an image")

        // Then
        #expect(output.sizeInPixels == CGSize(width: 533, height: 400))
    }

    @Test func thatImageIsntUpscaledByDefault() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 960, height: 960), unit: .pixels, contentMode: .aspectFill)

        // When
        let output = try #require(processor.process(Test.image), "Failed to process an image")

        // Then
        #expect(output.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func resizeToFitHeight() throws {
        // Given
        let processor = ImageProcessors.Resize(height: 300, unit: .pixels)

        // When
        let output = try #require(processor.process(Test.image), "Failed to process an image")

        // Then
        #expect(output.sizeInPixels == CGSize(width: 400, height: 300))
    }

    @Test func resizeToFitWidth() throws {
        // Given
        let processor = ImageProcessors.Resize(width: 400, unit: .pixels)

        // When
        let output = try #require(processor.process(Test.image), "Failed to process an image")

        // Then
        #expect(output.sizeInPixels == CGSize(width: 400, height: 300))
    }

    @Test func thatImageIsUpscaledIfOptionIsEnabled() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 960, height: 960), unit: .pixels, contentMode: .aspectFill, upscale: true)

        // When
        let output = try #require(processor.process(Test.image), "Failed to process an image")

        // Then
        #expect(output.sizeInPixels == CGSize(width: 1280, height: 960))
    }

    @Test func thatContentModeCanBeChangeToAspectFit() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 480, height: 480), unit: .pixels, contentMode: .aspectFit)

        // When
        let output = try #require(processor.process(Test.image), "Failed to process an image")

        // Then
        #expect(output.sizeInPixels == CGSize(width: 480, height: 360))
    }

    @Test func thatImageIsCropped() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, crop: true)

        // When
        let output = try #require(processor.process(Test.image), "Failed to process an image")

        // Then
        #expect(output.sizeInPixels == CGSize(width: 400, height: 400))
    }

    @Test func thatImageIsntCroppedWithAspectFitMode() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 480, height: 480), unit: .pixels, contentMode: .aspectFit, crop: true)

        // When
        let output = try #require(processor.process(Test.image), "Failed to process an image")

        // Then image is resized but isn't cropped
        #expect(output.sizeInPixels == CGSize(width: 480, height: 360))
    }

    @Test func extendedColorSpaceSupport() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 480, height: 480), unit: .pixels, contentMode: .aspectFit, crop: true)

        // When
        let output = try #require(processor.process(Test.image(named: "image-p3", extension: "jpg")), "Failed to process an image")

        // Then image is resized but isn't cropped
        #expect(output.sizeInPixels == CGSize(width: 480, height: 320))
        let colorSpace = try #require(output.cgImage?.colorSpace)
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
        #expect(colorSpace.isWideGamutRGB)
#elseif os(watchOS)
        #expect(!colorSpace.isWideGamutRGB)
#endif
    }

#if os(macOS)
    @Test
    @MainActor
    func resizeImageWithOrientationLeft() throws {
        // Given an image with `left` orientation. From the user perspective,
        // the image a landscape image with s size 640x480px. The raw pixel
        // data, on the other hand, is 480x640px. macOS, however, automatically
        // changes image orientaiton to `up` so that you don't have to worry about it
        let input = try #require(Test.image(named: "right-orientation.jpeg"))

        // When we resize the image to fit 320x480px frame, we expect the processor
        // to take image orientation into the account and produce a 320x240px.
        let processor = ImageProcessors.Resize(size: CGSize(width: 320, height: 1000), unit: .pixels, contentMode: .aspectFit)
        let output = try #require(processor.process(input), "Failed to process an image")

        // Then the image orientation is still `.left`
        #expect(output.sizeInPixels == CGSize(width: 320, height: 240))

        // Then the image is resized according to orientation
        #expect(output.size == CGSize(width: 320 / Screen.scale, height: 240 / Screen.scale))
    }
#endif

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    @Test func resizeImageWithOrientationLeft() throws {
        // Given an image with `right` orientation. From the user perspective,
        // the image a landscape image with s size 640x480px. The raw pixel
        // data, on the other hand, is 480x640px.
        let input = try #require(Test.image(named: "right-orientation.jpeg"))
        #expect(input.imageOrientation == .right)

        // When we resize the image to fit 320x480px frame, we expect the processor
        // to take image orientation into the account and produce a 320x240px.
        let processor = ImageProcessors.Resize(size: CGSize(width: 320, height: 1000), unit: .pixels, contentMode: .aspectFit)
        let output = try #require(processor.process(input), "Failed to process an image")

        // Then the image orientation is still `.right`
        #expect(output.sizeInPixels == CGSize(width: 240, height: 320))
        #expect(output.imageOrientation == .right)
        // Then the image is resized according to orientation
        #expect(output.size == CGSize(width: 320, height: 240))
    }

    @Test func resizeAndCropWithOrientationLeft() throws {
        // Given an image with `right` orientation. From the user perspective,
        // the image a landscape image with s size 640x480px. The raw pixel
        // data, on the other hand, is 480x640px.
        let input = try #require(Test.image(named: "right-orientation.jpeg"))
        #expect(input.imageOrientation == .right)

        // When
        let processor = ImageProcessors.Resize(size: CGSize(width: 320, height: 80), unit: .pixels, contentMode: .aspectFill, crop: true)
        let output = try #require(processor.process(input), "Failed to process an image")

        // Then
        #expect(output.sizeInPixels == CGSize(width: 80, height: 320))
        #expect(output.imageOrientation == .right)
        // Then
        #expect(output.size == CGSize(width: 320, height: 80))
    }
#endif

#if os(macOS)

#endif

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test func thatScalePreserved() throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)

        // When
        let image = try #require(processor.process(Test.image), "Failed to process an image")

        // Then
        #expect(image.scale == Test.image.scale)
    }
#endif

    @Test

    @MainActor
    func thatIdentifiersAreEqualWithSameParameters() {
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).identifier == ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).identifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), unit: .pixels).identifier == ImageProcessors.Resize(size: CGSize(width: 30 / Screen.scale, height: 30 / Screen.scale), unit: .points).identifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).identifier == ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).identifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).identifier == ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).identifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).identifier == ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).identifier
        )
    }

    @Test func thatIdentifiersAreNotEqualWithDifferentParameters() {
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).identifier != ImageProcessors.Resize(size: CGSize(width: 30, height: 40)).identifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).identifier != ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: false).identifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).identifier != ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: false).identifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).identifier != ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFill).identifier
        )
    }

    @Test

    @MainActor
    func thatHashableIdentifiersAreEqualWithSameParameters() {
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).hashableIdentifier == ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).hashableIdentifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), unit: .pixels).hashableIdentifier == ImageProcessors.Resize(size: CGSize(width: 30 / Screen.scale, height: 30 / Screen.scale), unit: .points).hashableIdentifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).hashableIdentifier == ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).hashableIdentifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).hashableIdentifier == ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).hashableIdentifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).hashableIdentifier == ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).hashableIdentifier
        )
    }

    @Test func thatHashableIdentifiersAreNotEqualWithDifferentParameters() {
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30)).hashableIdentifier != ImageProcessors.Resize(size: CGSize(width: 30, height: 40)).hashableIdentifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: true).hashableIdentifier != ImageProcessors.Resize(size: CGSize(width: 30, height: 30), crop: false).hashableIdentifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: true).hashableIdentifier != ImageProcessors.Resize(size: CGSize(width: 30, height: 30), upscale: false).hashableIdentifier
        )
        #expect(
            ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFit).hashableIdentifier != ImageProcessors.Resize(size: CGSize(width: 30, height: 30), contentMode: .aspectFill).hashableIdentifier
        )
    }

    @Test func description() {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 30, height: 30), unit: .pixels, contentMode: .aspectFit)

        // Then
        #expect(processor.description == "Resize(size: (30.0, 30.0) pixels, contentMode: .aspectFit, crop: false, upscale: false)")
    }

    // Just make sure these initializers are still available.
    @Test func initializer() {
        _ = ImageProcessors.Resize(height: 10)
        _ = ImageProcessors.Resize(width: 10)
        _ = ImageProcessors.Resize(width: 10, upscale: true)
        _ = ImageProcessors.Resize(width: 10, unit: .pixels, upscale: true)
    }
}

@Suite

struct CoreGraphicsExtensionsTests {
    @Test func scaleToFill() {
        #expect(1 == CGSize(width: 10, height: 10).scaleToFill(CGSize(width: 10, height: 10)))
        #expect(0.5 == CGSize(width: 20, height: 20).scaleToFill(CGSize(width: 10, height: 10)))
        #expect(2 == CGSize(width: 5, height: 5).scaleToFill(CGSize(width: 10, height: 10)))

        #expect(1 == CGSize(width: 20, height: 10).scaleToFill(CGSize(width: 10, height: 10)))
        #expect(1 == CGSize(width: 10, height: 20).scaleToFill(CGSize(width: 10, height: 10)))
        #expect(0.5 == CGSize(width: 30, height: 20).scaleToFill(CGSize(width: 10, height: 10)))
        #expect(0.5 == CGSize(width: 20, height: 30).scaleToFill(CGSize(width: 10, height: 10)))

        #expect(2 == CGSize(width: 5, height: 10).scaleToFill(CGSize(width: 10, height: 10)))
        #expect(2 == CGSize(width: 10, height: 5).scaleToFill(CGSize(width: 10, height: 10)))
        #expect(2 == CGSize(width: 5, height: 8).scaleToFill(CGSize(width: 10, height: 10)))
        #expect(2 == CGSize(width: 8, height: 5).scaleToFill(CGSize(width: 10, height: 10)))

        #expect(2 == CGSize(width: 30, height: 10).scaleToFill(CGSize(width: 10, height: 20)))
        #expect(2 == CGSize(width: 10, height: 30).scaleToFill(CGSize(width: 20, height: 10)))
    }

    @Test func scaleToFit() {
        #expect(1 == CGSize(width: 10, height: 10).scaleToFit(CGSize(width: 10, height: 10)))
        #expect(0.5 == CGSize(width: 20, height: 20).scaleToFit(CGSize(width: 10, height: 10)))
        #expect(2 == CGSize(width: 5, height: 5).scaleToFit(CGSize(width: 10, height: 10)))

        #expect(0.5 == CGSize(width: 20, height: 10).scaleToFit(CGSize(width: 10, height: 10)))
        #expect(0.5 == CGSize(width: 10, height: 20).scaleToFit(CGSize(width: 10, height: 10)))
        #expect(0.25 == CGSize(width: 40, height: 20).scaleToFit(CGSize(width: 10, height: 10)))
        #expect(0.25 == CGSize(width: 20, height: 40).scaleToFit(CGSize(width: 10, height: 10)))

        #expect(1 == CGSize(width: 5, height: 10).scaleToFit(CGSize(width: 10, height: 10)))
        #expect(1 == CGSize(width: 10, height: 5).scaleToFit(CGSize(width: 10, height: 10)))
        #expect(2 == CGSize(width: 2, height: 5).scaleToFit(CGSize(width: 10, height: 10)))
        #expect(2 == CGSize(width: 5, height: 2).scaleToFit(CGSize(width: 10, height: 10)))

        #expect(0.25 == CGSize(width: 40, height: 10).scaleToFit(CGSize(width: 10, height: 20)))
        #expect(0.25 == CGSize(width: 10, height: 40).scaleToFit(CGSize(width: 20, height: 10)))
    }

    @Test func centeredInRectWithSize() {
        #expect(
            CGSize(width: 10, height: 10).centeredInRectWithSize(CGSize(width: 10, height: 10)) == CGRect(x: 0, y: 0, width: 10, height: 10)
        )
        #expect(
            CGSize(width: 20, height: 20).centeredInRectWithSize(CGSize(width: 10, height: 10)) == CGRect(x: -5, y: -5, width: 20, height: 20)
        )
        #expect(
            CGSize(width: 20, height: 10).centeredInRectWithSize(CGSize(width: 10, height: 10)) == CGRect(x: -5, y: 0, width: 20, height: 10)
        )
        #expect(
            CGSize(width: 10, height: 20).centeredInRectWithSize(CGSize(width: 10, height: 10)) == CGRect(x: 0, y: -5, width: 10, height: 20)
        )
        #expect(
            CGSize(width: 10, height: 20).centeredInRectWithSize(CGSize(width: 10, height: 20)) == CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        #expect(
            CGSize(width: 10, height: 40).centeredInRectWithSize(CGSize(width: 10, height: 20)) == CGRect(x: 0, y: -10, width: 10, height: 40)
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

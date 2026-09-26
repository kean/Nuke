// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

#if !os(macOS)
import UIKit
#else
import AppKit
#endif

/// The geometry and the pixel formats of ``ImageProcessors/Resize`` beyond the
/// landscape fixture the basic tests use.
@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsResizeBehaviorTests {

    // MARK: - Portrait Images

    @Test func aspectFillOfPortraitImageFillsTheWidth() throws {
        // Given a 100x200 image
        let input = Test.rgbImage(width: 100, height: 200)
        let processor = ImageProcessors.Resize(size: CGSize(width: 50, height: 50), unit: .pixels, contentMode: .aspectFill)

        // When
        let output = try #require(processor.process(input))

        // Then the shorter side matches the target and the other one overflows
        #expect(output.sizeInPixels == CGSize(width: 50, height: 100))
    }

    @Test func aspectFitOfPortraitImageFitsTheHeight() throws {
        // Given a 100x200 image
        let input = Test.rgbImage(width: 100, height: 200)
        let processor = ImageProcessors.Resize(size: CGSize(width: 50, height: 50), unit: .pixels, contentMode: .aspectFit)

        // When
        let output = try #require(processor.process(input))

        // Then the longer side matches the target
        #expect(output.sizeInPixels == CGSize(width: 25, height: 50))
    }

    @Test func resizeToWidthOfPortraitImage() throws {
        // Given
        let input = Test.rgbImage(width: 100, height: 200)

        // When
        let output = try #require(ImageProcessors.Resize(width: 50, unit: .pixels).process(input))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 50, height: 100))
    }

    @Test func resizeToHeightWithUpscale() throws {
        // Given a 640x480 image
        let processor = ImageProcessors.Resize(height: 960, unit: .pixels, upscale: true)

        // When
        let output = try #require(processor.process(Test.image))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 1280, height: 960))
    }

    // MARK: - No Upscaling

    @Test(arguments: [ImageProcessingOptions.ContentMode.aspectFill, .aspectFit])
    func resizingToTheExactSizeReturnsTheInput(contentMode: ImageProcessingOptions.ContentMode) throws {
        // Given
        let input = Test.rgbImage(width: 40, height: 30)
        let processor = ImageProcessors.Resize(size: CGSize(width: 40, height: 30), unit: .pixels, contentMode: contentMode)

        // When
        let output = try #require(processor.process(input))

        // Then there is nothing to scale and the image isn't redrawn
        #expect(output === input)
    }

    @Test func resizeToWidthDoesNotUpscaleByDefault() throws {
        // Given
        let input = Test.image

        // When
        let output = try #require(ImageProcessors.Resize(width: 1280, unit: .pixels).process(input))

        // Then
        #expect(output === input)
    }

    /// Filling a 1000x100 target would require enlarging a 640x480 image, so
    /// without `upscale` it is left alone, even though one of its sides is
    /// larger than the target.
    @Test func aspectFillThatRequiresUpscalingLeavesTheImageAlone() throws {
        // Given
        let input = Test.image
        let processor = ImageProcessors.Resize(size: CGSize(width: 1000, height: 100), unit: .pixels, contentMode: .aspectFill)

        // When
        let output = try #require(processor.process(input))

        // Then
        #expect(output === input)
    }

    @Test func cropThatRequiresUpscalingCropsToTheTargetAspectRatio() throws {
        // Given a 640x480 image and a 10:1 target that would need enlarging
        let processor = ImageProcessors.Resize(size: CGSize(width: 1000, height: 100), unit: .pixels, crop: true)

        // When
        let output = try #require(processor.process(Test.image))

        // Then it is cropped to 10:1 at its native resolution
        #expect(output.sizeInPixels == CGSize(width: 640, height: 64))
    }

    // MARK: - Smallest Output

    @Test(arguments: [ImageProcessingOptions.ContentMode.aspectFill, .aspectFit], [false, true])
    func downscalingToASinglePixel(contentMode: ImageProcessingOptions.ContentMode, crop: Bool) throws {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 1, height: 1), unit: .pixels, contentMode: contentMode, crop: crop)

        // When
        let output = try #require(processor.process(Test.image))

        // Then a 4:3 image can't be any smaller than a single pixel
        #expect(output.sizeInPixels == CGSize(width: 1, height: 1))
    }

    // MARK: - Cropping

    /// The crop is centered: of three vertical stripes, only the middle one is
    /// expected to survive a square crop.
    @Test func cropKeepsTheCenterOfLandscapeImage() throws {
        // Given a 600x200 image with red, green, and blue vertical stripes
        let input = Test.stripedImage(width: 600, height: 200, isVertical: true)
        let processor = ImageProcessors.Resize(size: CGSize(width: 100, height: 100), unit: .pixels, crop: true)

        // When
        let output = try #require(processor.process(input))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 100, height: 100))
        let stripes = try #require(RGBABitmap(image: input))
        let middle = stripes.color(atX: 300, y: 100)
        let pixels = try #require(RGBABitmap(image: output))
        for (x, y) in [(10, 10), (50, 50), (90, 90), (10, 90), (90, 10)] {
            #expect(pixels.color(atX: x, y: y).isClose(to: middle), "(\(x), \(y))")
        }
        #expect(!middle.isClose(to: stripes.color(atX: 100, y: 100)))
        #expect(!middle.isClose(to: stripes.color(atX: 500, y: 100)))
    }

    @Test func cropKeepsTheCenterOfPortraitImage() throws {
        // Given a 200x600 image with red, green, and blue horizontal stripes
        let input = Test.stripedImage(width: 200, height: 600, isVertical: false)
        let processor = ImageProcessors.Resize(size: CGSize(width: 100, height: 100), unit: .pixels, crop: true)

        // When
        let output = try #require(processor.process(input))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 100, height: 100))
        let stripes = try #require(RGBABitmap(image: input))
        let middle = stripes.color(atX: 100, y: 300)
        let pixels = try #require(RGBABitmap(image: output))
        for (x, y) in [(10, 10), (50, 50), (90, 90), (10, 90), (90, 10)] {
            #expect(pixels.color(atX: x, y: y).isClose(to: middle), "(\(x), \(y))")
        }
        #expect(!middle.isClose(to: stripes.color(atX: 100, y: 100)))
        #expect(!middle.isClose(to: stripes.color(atX: 100, y: 500)))
    }

    // MARK: - Pixel Formats

    /// `ImageEncoders.Default` picks JPEG or PNG based on the alpha channel,
    /// so a resized photo that gained one would be stored as a PNG.
    @Test func resizingKeepsOpaqueImagesOpaque() throws {
        // Given
        let input = Test.image
        #expect(input.cgImage?.isOpaque == true)

        // When
        let output = try #require(ImageProcessors.Resize(size: CGSize(width: 100, height: 100), unit: .pixels).process(input))

        // Then
        #expect(output.cgImage?.isOpaque == true)
        let data = try #require(ImageEncoders.Default().encode(output))
        #expect(AssetType(data) == .jpeg)
    }

    @Test func resizingKeepsTheTransparencyOfTransparentImages() throws {
        // Given an 80x80 transparent image with an opaque square in the middle
        let input = Test.imageWithOpaqueSquare(size: 80, square: 40)

        // When
        let output = try #require(ImageProcessors.Resize(size: CGSize(width: 40, height: 40), unit: .pixels).process(input))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 40, height: 40))
        #expect(output.cgImage?.isOpaque == false)
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.alpha(atX: 1, y: 1) == 0)
        #expect(pixels.alpha(atX: 20, y: 20) == 255)
    }

    /// - seealso: https://github.com/kean/Nuke/issues/782
    @Test func resizingKeepsGrayscaleImagesGrayscale() throws {
        // Given an 8 bpp grayscale image
        let input = Test.image(named: "grayscale", extension: "jpeg")
        #expect(input.cgImage?.bitsPerPixel == 8)

        // When
        let output = try #require(ImageProcessors.Resize(size: CGSize(width: 50, height: 50), unit: .pixels).process(input))

        // Then
        let cgImage = try #require(output.cgImage)
        #expect(cgImage.colorSpace?.model == .monochrome)
        #expect(cgImage.bitsPerPixel == 8)
        #expect(cgImage.isOpaque)
    }

    @Test func resizing16BitImage() throws {
        // Given an image with 16 bits per component
        let input = PlatformImage(cgImage: try #require(Test.makeImage(width: 40, height: 30, bitsPerComponent: 16, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))))

        // When
        let output = try #require(ImageProcessors.Resize(size: CGSize(width: 20, height: 20), unit: .pixels).process(input))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 27, height: 20))
    }

    // MARK: - Images Without a Bitmap

    @Test(arguments: [false, true])
    func resizingAnImageWithoutCGImageFails(crop: Bool) {
        // Given
        let processor = ImageProcessors.Resize(size: CGSize(width: 10, height: 10), unit: .pixels, crop: crop)

        // Then the processing fails instead of returning an empty image
        #expect(processor.process(PlatformImage()) == nil)
        #expect(throws: ImageProcessingError.self) {
            try processor.process(ImageContainer(image: PlatformImage()), context: .mock)
        }
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    // MARK: - Scale

    @Test func resizingPreservesTheScaleOfTheInput() throws {
        // Given a @3x image
        let input = UIImage(cgImage: try #require(Test.image.cgImage), scale: 3, orientation: .up)

        // When
        let output = try #require(ImageProcessors.Resize(size: CGSize(width: 300, height: 300), unit: .pixels, crop: true).process(input))

        // Then
        #expect(output.scale == 3)
        #expect(output.sizeInPixels == CGSize(width: 300, height: 300))
        #expect(output.size == CGSize(width: 100, height: 100))
    }
#endif
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsGaussianBlurTests {
    @Test func applyBlur() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()
        #expect(!processor.description.isEmpty)

        // When
        #expect(processor.process(image) != nil)
    }

    @Test func applyBlurProducesImagesBackedByCoreGraphics() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        #expect(processor.process(image) != nil)
    }

    @Test func applyBlurPreservesOpacityOfOpaqueImages() throws {
        // Given an opaque image
        let image = Test.image
        #expect(image.cgImage?.isOpaque == true)
        let processor = ImageProcessors.GaussianBlur()

        // When
        let processed = try #require(processor.process(image))

        // Then the output isn't tagged with an alpha channel: it would make
        // `ImageEncoders.Default` encode it as PNG instead of JPEG/HEIC
        #expect(processed.cgImage?.isOpaque == true)
    }

    @Test func applyBlurPreservesAlphaChannelOfTransparentImages() throws {
        // Given an image with an alpha channel
        let image = Test.image(named: "swift", extension: "png")
        #expect(image.cgImage?.isOpaque == false)
        let processor = ImageProcessors.GaussianBlur()

        // When
        let processed = try #require(processor.process(image))

        // Then
        #expect(processed.cgImage?.isOpaque == false)
    }

    @Test func blurSpreadsAlphaOfTransparentImages() throws {
        // GIVEN an opaque square in the middle of a transparent canvas
        let image = imageWithOpaqueSquare(size: 64, square: 16)
        let outsideTheSquare = 32 * 64 + 20 // (x: 20, y: 32)
        #expect(try alphaChannel(of: image)[outsideTheSquare] == 0)

        // WHEN
        let output = try #require(ImageProcessors.GaussianBlur(radius: 8).process(image))

        // THEN the alpha channel is blurred too: it bleeds outside of the
        // square and the solid core softens
        let alpha = try alphaChannel(of: output)
        #expect(alpha[outsideTheSquare] > 0)
        #expect(alpha.max() ?? 0 < 255)
    }

    @Test func imagesWithSameRadiusHasSameIdentifiers() {
        #expect(
            ImageProcessors.GaussianBlur(radius: 2).identifier ==
            ImageProcessors.GaussianBlur(radius: 2).identifier
        )
    }

    @Test func imagesWithDifferentRadiusHasDifferentIdentifiers() {
        #expect(
            ImageProcessors.GaussianBlur(radius: 2).identifier !=
            ImageProcessors.GaussianBlur(radius: 3).identifier
        )
    }

    @Test func imagesWithSameRadiusHasSameHashableIdentifiers() {
        #expect(
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier ==
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier
        )
    }

    @Test func imagesWithDifferentRadiusHasDifferentHashableIdentifiers() {
        #expect(
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier !=
            ImageProcessors.GaussianBlur(radius: 3).hashableIdentifier
        )
    }

    // MARK: - Output Dimensions

    @Test func blurDoesNotChangeImageDimensions() throws {
        // GIVEN
        let image = Test.image
        let inputSize = image.sizeInPixels
        let processor = ImageProcessors.GaussianBlur(radius: 8)

        // WHEN
        let output = try #require(processor.process(image))

        // THEN - blurring must not alter the canvas size
        #expect(output.sizeInPixels == inputSize)
    }

    @Test func blurWithMinimumRadiusProducesOutput() throws {
        // GIVEN - radius of 1 is the smallest non-trivial blur
        let processor = ImageProcessors.GaussianBlur(radius: 1)

        // WHEN / THEN - must not crash and must return a valid image
        let output = try #require(processor.process(Test.image))
        #expect(output.sizeInPixels == Test.image.sizeInPixels)
    }

    @Test func blurGrayscaleImageDoesNotCrash() throws {
        // GIVEN - a grayscale (monochrome color space) source. Its 16-bit
        // gray+alpha scratch context used to crash vImageBoxConvolve.
        let image = Test.grayscaleImage(width: 400, height: 225)
        let processor = ImageProcessors.GaussianBlur(radius: 8)

        // WHEN / THEN - must not crash and must return a same-size image
        let output = try #require(processor.process(image))
        #expect(output.sizeInPixels == CGSize(width: 400, height: 225))
    }

    @Test func differentRadiiProduceDifferentDescriptions() {
        #expect(
            ImageProcessors.GaussianBlur(radius: 4).description !=
            ImageProcessors.GaussianBlur(radius: 16).description
        )
    }

    // MARK: - Zero and Negative Radius

    @Test func zeroRadiusReturnsTheImageUnchanged() throws {
        // GIVEN
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur(radius: 0)

        // WHEN
        let output = try #require(processor.process(image))

        // THEN the processor is an identity transform
        #expect(output === image)
    }

    @Test func negativeRadiusIsClampedToZero() throws {
        // GIVEN
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur(radius: -8)

        // WHEN
        let output = try #require(processor.process(image))

        // THEN the image is returned unchanged and the processor is
        // indistinguishable from the one with a radius of `0`
        #expect(output === image)
        #expect(processor.identifier == ImageProcessors.GaussianBlur(radius: 0).identifier)
        #expect(processor.hashableIdentifier == ImageProcessors.GaussianBlur(radius: 0).hashableIdentifier)
        #expect(processor == ImageProcessors.GaussianBlur(radius: 0))
    }

    @Test func zeroRadiusIsDistinctFromTheSmallestBlur() throws {
        // GIVEN
        let image = Test.image

        // WHEN
        let identity = try #require(ImageProcessors.GaussianBlur(radius: 0).process(image))
        let blurred = try #require(ImageProcessors.GaussianBlur(radius: 1).process(image))

        // THEN a radius of `1` does blur the image
        #expect(try pixels(of: identity) != pixels(of: blurred))
    }

    @Test func smallRadiiProduceDifferentOutput() throws {
        // GIVEN - processors with distinct identifiers, so they must not
        // produce byte-identical output and populate the cache with duplicates
        let image = Test.image

        // WHEN
        let outputs = try (1...3).map {
            try pixels(of: #require(ImageProcessors.GaussianBlur(radius: $0).process(image)))
        }

        // THEN
        #expect(outputs[0] != outputs[1])
        #expect(outputs[1] != outputs[2])
    }
}

/// Renders the image into a known ARGB context and returns the raw bytes.
private func pixels(of image: PlatformImage) throws -> Data {
    let cgImage = try #require(image.cgImage)
    let bytesPerRow = cgImage.width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * cgImage.height)
    let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return true
    }
    #expect(success)
    return Data(bytes)
}

/// Returns the alpha component of every pixel of the image, row by row.
private func alphaChannel(of image: PlatformImage) throws -> [UInt8] {
    let pixels = try pixels(of: image)
    return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
}

/// Returns a transparent image with an opaque square in the middle.
private func imageWithOpaqueSquare(size: Int, square: Int) -> PlatformImage {
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    let origin = (size - square) / 2
    context.fill(CGRect(x: origin, y: origin, width: square, height: square))
    return PlatformImage(cgImage: context.makeImage()!)
}

#endif

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

    // MARK: - Edges

    /// A blur averages neighboring pixels, so a solid color has nothing to
    /// blur. With the edge extension, that holds all the way to the edges –
    /// including for the kernels larger than the image itself. Without it, the
    /// edges would be darkened by the transparent black outside the image.
    ///
    /// A radius of `1544` or more used to overflow the `Int32` sums in vImage
    /// and come back nearly black; the kernel is capped now.
    ///
    /// - seealso: https://github.com/kean/Nuke/issues/308
    @Test(arguments: [1, 8, 50, 500, 1544, 2000])
    func blurringASolidColorLeavesItUnchanged(radius: Int) throws {
        // Given a 40x40 solid color image
        let image = Test.rgbImage(width: 40, height: 40, color: CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))

        // When
        let output = try #require(ImageProcessors.GaussianBlur(radius: radius).process(image))

        // Then every pixel, including the ones at the edges, keeps its color
        let expected = try pixels(of: image)
        let actual = try pixels(of: output)
        #expect(actual.count == expected.count)
        let maxDifference = zip(actual, expected).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(maxDifference <= 1)
    }

    @Test func blurringWithLargeRadiusDoesNotCorruptTheImage() throws {
        // GIVEN a 1000x1000 image with a red left half and a blue right half
        let image = imageWithTwoHalves(size: 1000)

        // WHEN blurring with a radius past the kernel cap
        let input = try pixels(of: image)
        let output = try pixels(of: #require(ImageProcessors.GaussianBlur(radius: 2000).process(image)))

        // THEN the center pixel is the average of both halves instead of
        // near-black
        let left = (500 * 1000 + 250) * 4
        let right = (500 * 1000 + 750) * 4
        let center = (500 * 1000 + 500) * 4
        for channel in 0..<4 {
            let expected = (Int(input[left + channel]) + Int(input[right + channel])) / 2
            #expect(abs(Int(output[center + channel]) - expected) <= 8, "channel \(channel)")
        }
    }

    @Test func extendedColorSpaceSupport() throws {
        // GIVEN a Display P3 image
        let input = Test.image(named: "image-p3", extension: "jpg")
        #expect(try #require(input.cgImage?.colorSpace).isWideGamutRGB)

        // WHEN
        let output = try #require(ImageProcessors.GaussianBlur(radius: 4).process(input))

        // THEN the image keeps its wide-gamut color space instead of being
        // clipped to device RGB
        let colorSpace = try #require(output.cgImage?.colorSpace)
        #expect(colorSpace.isWideGamutRGB)
        #expect(output.cgImage?.isOpaque == true)
    }

    /// The blur runs on premultiplied pixels, which is what keeps the edges of
    /// a shape from turning dark as they fade out: the color of a translucent
    /// pixel, once its alpha is divided out, is still the color of the shape.
    @Test func blurDoesNotDarkenTheEdgesOfTransparentShapes() throws {
        // GIVEN an opaque square in the middle of a transparent canvas
        let image = imageWithOpaqueSquare(size: 64, square: 16)
        let input = try pixels(of: image)
        let center = (32 * 64 + 32) * 4
        #expect(input[center + 3] == 255)

        // WHEN
        let output = try pixels(of: #require(ImageProcessors.GaussianBlur(radius: 4).process(image)))

        // THEN
        var translucentPixelCount = 0
        for offset in stride(from: 0, to: output.count, by: 4) {
            let alpha = Int(output[offset + 3])
            guard alpha > 64 && alpha < 224 else { continue }
            translucentPixelCount += 1
            for channel in 0..<3 {
                let unpremultiplied = Int(output[offset + channel]) * 255 / alpha
                #expect(abs(unpremultiplied - Int(input[center + channel])) <= 12, "pixel \(offset / 4), channel \(channel)")
            }
        }
        #expect(translucentPixelCount > 0)
    }

    @Test func blurringCMYKImage() throws {
        // Given an image in a color space vImage can't process directly
        let context = try #require(CGContext(
            data: nil,
            width: 40,
            height: 30,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceCMYK(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        let image = PlatformImage(cgImage: try #require(context.makeImage()))

        // When
        let output = try #require(ImageProcessors.GaussianBlur(radius: 4).process(image))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 40, height: 30))
        #expect(output.cgImage?.isOpaque == true)
    }

    @Test func blurringAnImageWithoutCGImageFails() {
        #expect(ImageProcessors.GaussianBlur(radius: 4).process(PlatformImage()) == nil)
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test func blurPreservesScaleAndOrientation() throws {
        // Given a @3x image rotated by the orientation
        let input = UIImage(cgImage: try #require(Test.image.cgImage), scale: 3, orientation: .right)

        // When
        let output = try #require(ImageProcessors.GaussianBlur(radius: 4).process(input))

        // Then
        #expect(output.scale == 3)
        #expect(output.imageOrientation == .right)
        #expect(output.size == input.size)
    }
#endif
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

/// Returns an opaque square image with a red left half and a blue right half.
private func imageWithTwoHalves(size: Int) -> PlatformImage {
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: size / 2, y: 0, width: size / 2, height: size))
    return PlatformImage(cgImage: context.makeImage()!)
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

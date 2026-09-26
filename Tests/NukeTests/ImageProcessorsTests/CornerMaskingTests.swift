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

/// The pixels ``ImageProcessors/Circle`` and ``ImageProcessors/RoundedCorners``
/// produce, on every platform.
@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsCornerMaskingTests {

    // MARK: - Circle

    @Test func circleCropsLandscapeImageToTheCenteredSquare() throws {
        // Given a 90x30 image with red, green, and blue vertical stripes
        let input = Test.stripedImage(width: 90, height: 30, isVertical: true)

        // When
        let output = try #require(ImageProcessors.Circle().process(input))

        // Then only the middle stripe is left, masked by a circle
        #expect(output.sizeInPixels == CGSize(width: 30, height: 30))
        let stripes = try #require(RGBABitmap(image: input))
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.alpha(atX: 15, y: 15) == 255)
        #expect(pixels.color(atX: 15, y: 15).isClose(to: stripes.color(atX: 45, y: 15)))
        #expect(!pixels.color(atX: 15, y: 15).isClose(to: stripes.color(atX: 15, y: 15)))
        for (x, y) in [(0, 0), (29, 0), (0, 29), (29, 29)] {
            #expect(pixels.alpha(atX: x, y: y) == 0, "(\(x), \(y))")
        }
    }

    @Test func circleCropsPortraitImageToTheCenteredSquare() throws {
        // Given a 30x90 image with red, green, and blue horizontal stripes
        let input = Test.stripedImage(width: 30, height: 90, isVertical: false)

        // When
        let output = try #require(ImageProcessors.Circle().process(input))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 30, height: 30))
        let stripes = try #require(RGBABitmap(image: input))
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.color(atX: 15, y: 15).isClose(to: stripes.color(atX: 15, y: 45)))
    }

    @Test func circleKeepsThePixelsInsideTheCircle() throws {
        // Given
        let input = Test.rgbImage(width: 40, height: 40)

        // When
        let output = try #require(ImageProcessors.Circle().process(input))

        // Then the points of the inscribed circle close to its edge are kept
        // and the ones just outside of it are cut off
        #expect(output.sizeInPixels == CGSize(width: 40, height: 40))
        let pixels = try #require(RGBABitmap(image: output))
        for (x, y) in [(20, 1), (1, 20), (38, 20), (20, 38)] {
            #expect(pixels.alpha(atX: x, y: y) == 255, "(\(x), \(y))")
        }
        for (x, y) in [(4, 4), (35, 4), (4, 35), (35, 35)] {
            #expect(pixels.alpha(atX: x, y: y) == 0, "(\(x), \(y))")
        }
    }

    @Test func circleOfSinglePixelImage() throws {
        // Given the smallest possible image
        let input = Test.rgbImage(width: 1, height: 1)

        // When
        let output = try #require(ImageProcessors.Circle().process(input))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 1, height: 1))
    }

    @Test func circleWithBorderStrokesTheEdgeOfTheCircle() throws {
        // Given a blue image
        let input = Test.rgbImage(width: 60, height: 60, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let border = ImageProcessingOptions.Border(color: .red, width: 8, unit: .pixels)

        // When
        let output = try #require(ImageProcessors.Circle(border: border).process(input))

        // Then the edge is red, and the rest of the image isn't
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.red(atX: 30, y: 1) > 200)
        #expect(pixels.red(atX: 1, y: 30) > 200)
        #expect(pixels.red(atX: 30, y: 30) < 50)
        #expect(pixels.alpha(atX: 0, y: 0) == 0)
    }

    // MARK: - Rounded Corners

    @Test func roundedCornersOfNonSquareImage() throws {
        // Given
        let input = Test.rgbImage(width: 60, height: 30)

        // When
        let output = try #require(ImageProcessors.RoundedCorners(radius: 10, unit: .pixels).process(input))

        // Then the size is preserved, the corners are cut off, and the edges
        // between them are kept
        #expect(output.sizeInPixels == CGSize(width: 60, height: 30))
        let pixels = try #require(RGBABitmap(image: output))
        for (x, y) in [(0, 0), (59, 0), (0, 29), (59, 29)] {
            #expect(pixels.alpha(atX: x, y: y) == 0, "(\(x), \(y))")
        }
        for (x, y) in [(30, 0), (30, 29), (0, 15), (59, 15)] {
            #expect(pixels.alpha(atX: x, y: y) == 255, "(\(x), \(y))")
        }
    }

    /// A radius that doesn't fit is a common consequence of rounding a
    /// thumbnail with a radius meant for a bigger image, or of using points on
    /// a high-density screen. Core Graphics documents the radius of a rounded
    /// rect as having to fit, so the processor must not crash on it.
    @Test(arguments: [CGFloat(21), 40, 1000])
    func roundedCornersWithRadiusLargerThanHalfTheImage(radius: CGFloat) throws {
        // Given a 40x40 image
        let input = Test.rgbImage(width: 40, height: 40)

        // When
        let output = try #require(ImageProcessors.RoundedCorners(radius: radius, unit: .pixels).process(input))

        // Then it is rounded as much as it can be
        #expect(output.sizeInPixels == CGSize(width: 40, height: 40))
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.alpha(atX: 0, y: 0) == 0)
        #expect(pixels.alpha(atX: 4, y: 4) == 0)
        #expect(pixels.alpha(atX: 20, y: 20) == 255)
    }

    @Test(arguments: [CGFloat(0), -8])
    func roundedCornersWithZeroOrNegativeRadiusKeepTheCorners(radius: CGFloat) throws {
        // Given
        let input = Test.rgbImage(width: 20, height: 20)

        // When
        let output = try #require(ImageProcessors.RoundedCorners(radius: radius, unit: .pixels).process(input))

        // Then it doesn't crash and the image is kept whole, corners included
        #expect(output.sizeInPixels == CGSize(width: 20, height: 20))
        let pixels = try #require(RGBABitmap(image: output))
        for (x, y) in [(0, 0), (19, 0), (0, 19), (19, 19), (10, 10)] {
            #expect(pixels.alpha(atX: x, y: y) == 255, "(\(x), \(y))")
        }
    }

    // MARK: - Encoding

    /// The corners are transparent, so the processed image has to keep an
    /// alpha channel – or the disk cache stores it as a JPEG with black corners.
    @Test func maskedImagesAreEncodedWithTransparency() throws {
        // Given an opaque image
        let input = Test.image
        #expect(input.cgImage?.isOpaque == true)

        for processor in [ImageProcessors.Circle() as any ImageProcessing, ImageProcessors.RoundedCorners(radius: 16, unit: .pixels)] {
            // When
            let output = try #require(processor.process(input))
            let data = try #require(ImageEncoders.Default().encode(output))

            // Then
            #expect(output.cgImage?.isOpaque == false)
            #expect(AssetType(data) == .png)
            let decoded = try ImageDecoders.Default().decode(data)
            let pixels = try #require(RGBABitmap(image: decoded.image))
            #expect(pixels.alpha(atX: 0, y: 0) == 0)
        }
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    // MARK: - Scale and Orientation

    @Test func maskingPreservesScaleAndOrientation() throws {
        // Given a @3x image rotated by the orientation
        let input = UIImage(cgImage: try #require(Test.image.cgImage), scale: 3, orientation: .right)

        for processor in [ImageProcessors.Circle() as any ImageProcessing, ImageProcessors.RoundedCorners(radius: 16, unit: .pixels)] {
            // When
            let output = try #require(processor.process(input))

            // Then
            #expect(output.scale == 3)
            #expect(output.imageOrientation == .right)
        }
    }
#endif
}

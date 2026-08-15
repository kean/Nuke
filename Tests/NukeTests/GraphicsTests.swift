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

/// Tests for the internal drawing primitives shared by the image processors.
/// The processors that use them (``ImageProcessors/Circle``,
/// ``ImageProcessors/RoundedCorners``) are unavailable on macOS, so these
/// exercise the underlying code paths directly on every platform.
@Suite(.timeLimit(.minutes(5)))
struct GraphicsTests {

    // MARK: - Cropping to Square

    @Test func croppingToSquareCropsTheLongerSide() throws {
        // Given a 640x480 image
        let input = Test.image

        // When
        let output = try #require(input.processed.byCroppingToSquare())

        // Then it is cropped to the shorter side
        #expect(output.sizeInPixels == CGSize(width: 480, height: 480))
    }

    @Test func croppingToSquareReturnsTheInputWhenAlreadySquare() throws {
        // Given
        let input = Test.rgbImage(width: 40, height: 40)

        // When
        let output = try #require(input.processed.byCroppingToSquare())

        // Then the input is returned as is (no redrawing)
        #expect(output === input)
    }

    @Test func croppingToSquareCropsTheTallerSide() throws {
        // Given
        let input = Test.rgbImage(width: 40, height: 100)

        // When
        let output = try #require(input.processed.byCroppingToSquare())

        // Then
        #expect(output.sizeInPixels == CGSize(width: 40, height: 40))
    }

    // MARK: - Drawing in Circle

    @Test func drawingInCircleProducesASquareWithTransparentCorners() throws {
        // Given a non-square image
        let input = Test.rgbImage(width: 100, height: 60)

        // When
        let output = try #require(input.processed.byDrawingInCircle(border: nil))

        // Then the image is cropped to a square and the corners are cut off
        #expect(output.sizeInPixels == CGSize(width: 60, height: 60))
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.alpha(atX: 0, y: 0) == 0)
        #expect(pixels.alpha(atX: 59, y: 59) == 0)
        #expect(pixels.alpha(atX: 30, y: 30) == 255)
    }

    @Test func drawingInCircleWithBorder() throws {
        // Given
        let input = Test.rgbImage(width: 60, height: 60)
        let border = ImageProcessingOptions.Border(color: .red, width: 4, unit: .pixels)

        // When
        let output = try #require(input.processed.byDrawingInCircle(border: border))

        // Then the size is preserved and the corners are still cut off
        #expect(output.sizeInPixels == CGSize(width: 60, height: 60))
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.alpha(atX: 0, y: 0) == 0)
        #expect(pixels.alpha(atX: 30, y: 30) == 255)
    }

    // MARK: - Rounded Corners

    @Test func addingRoundedCornersPreservesSizeAndCutsTheCorners() throws {
        // Given
        let input = Test.rgbImage(width: 60, height: 60)

        // When
        let output = try #require(input.processed.byAddingRoundedCorners(radius: 20))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 60, height: 60))
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.alpha(atX: 0, y: 0) == 0)
        #expect(pixels.alpha(atX: 30, y: 30) == 255)
    }

    @Test func addingRoundedCornersWithBorderDrawsTheBorder() throws {
        // Given an image with no red in it
        let input = Test.rgbImage(width: 60, height: 60, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let border = ImageProcessingOptions.Border(color: .red, width: 6, unit: .pixels)

        // When
        let output = try #require(input.processed.byAddingRoundedCorners(radius: 4, border: border))

        // Then the border is stroked along the edge
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.red(atX: 30, y: 1) > 100)
        // ...and the center is left untouched
        #expect(pixels.red(atX: 30, y: 30) < 100)
    }

    /// Rounding the corners requires an alpha channel, which the monochrome
    /// color space of the input doesn't have. The context creation is expected
    /// to recover instead of returning `nil`.
    ///
    /// - seealso: https://github.com/kean/Nuke/issues/35
    @Test func addingRoundedCornersToGrayscaleImage() throws {
        // Given
        let input = Test.grayscaleImage(width: 40, height: 40)

        // When
        let output = try #require(input.processed.byAddingRoundedCorners(radius: 10))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 40, height: 40))
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.alpha(atX: 0, y: 0) == 0)
        #expect(pixels.alpha(atX: 20, y: 20) == 255)
    }

    // MARK: - Drawing in Canvas

    @Test func drawingInCanvasWithSize() throws {
        // Given
        let input = Test.rgbImage(width: 40, height: 40)

        // When
        let output = try #require(input.draw(inCanvasWithSize: CGSize(width: 20, height: 30)))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 20, height: 30))
    }

    @Test func drawingInCanvasWithDrawRect() throws {
        // Given
        let input = Test.rgbImage(width: 40, height: 40, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))

        // When the image is drawn into one quadrant of a larger canvas
        let output = try #require(input.draw(
            inCanvasWithSize: CGSize(width: 80, height: 80),
            drawRect: CGRect(x: 40, y: 40, width: 40, height: 40)
        ))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 80, height: 80))
        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.red(atX: 60, y: 20) > 200) // The image was drawn here
        #expect(pixels.red(atX: 5, y: 5) == 0) // ...and nothing here
    }

    // MARK: - Resizing

    @Test func resizingDoesNotUpscaleByDefault() throws {
        // Given
        let input = Test.rgbImage(width: 40, height: 40)

        // When
        let output = try #require(input.processed.byResizing(
            to: CGSize(width: 100, height: 100),
            contentMode: .aspectFill,
            upscale: false
        ))

        // Then the input is returned as is
        #expect(output === input)
    }

    @Test func resizingUpscalesWhenRequested() throws {
        // Given
        let input = Test.rgbImage(width: 40, height: 40)

        // When
        let output = try #require(input.processed.byResizing(
            to: CGSize(width: 100, height: 100),
            contentMode: .aspectFill,
            upscale: true
        ))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 100, height: 100))
    }

    @Test func resizingAndCroppingUpscalesWhenRequested() throws {
        // Given
        let input = Test.rgbImage(width: 40, height: 20)

        // When
        let output = try #require(input.processed.byResizingAndCropping(to: CGSize(width: 100, height: 100), upscale: true))

        // Then
        #expect(output.sizeInPixels == CGSize(width: 100, height: 100))
    }

    // MARK: - Images Without a Backing CGImage

    @Test func drawingPrimitivesReturnNilForImagesWithoutCGImage() {
        // Given an image with no backing `CGImage`
        let input = PlatformImage()
        #expect(input.cgImage == nil)

        // Then every drawing primitive bails out instead of crashing
        #expect(input.processed.byCroppingToSquare() == nil)
        #expect(input.processed.byDrawingInCircle(border: nil) == nil)
        #expect(input.processed.byAddingRoundedCorners(radius: 10) == nil)
        #expect(input.draw(inCanvasWithSize: CGSize(width: 10, height: 10)) == nil)
        #expect(input.processed.byResizing(to: CGSize(width: 10, height: 10), contentMode: .aspectFill, upscale: true) == nil)
        #expect(input.processed.byResizingAndCropping(to: CGSize(width: 10, height: 10), upscale: true) == nil)
        #expect(input.decompressed(isUsingPrepareForDisplay: false) == nil)
    }
}

// MARK: - Helpers

/// Reads the image into a known RGBA (premultiplied last) bitmap so that the
/// individual pixels can be inspected regardless of the source color space.
private struct RGBABitmap {
    private let bytes: [UInt8]
    private let bytesPerRow: Int

    init?(image: PlatformImage) {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        self.bytesPerRow = bytesPerRow
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let isSuccess = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard isSuccess else { return nil }
        self.bytes = bytes
    }

    func red(atX x: Int, y: Int) -> UInt8 {
        bytes[y * bytesPerRow + x * 4]
    }

    func alpha(atX x: Int, y: Int) -> UInt8 {
        bytes[y * bytesPerRow + x * 4 + 3]
    }
}

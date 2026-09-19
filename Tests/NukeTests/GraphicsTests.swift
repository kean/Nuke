// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
import ImageIO
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

    // MARK: - Invalid Target Sizes

    /// The target sizes come straight from the user and converting a non-finite
    /// `CGFloat` to an `Int` traps, so the invalid sizes have to be rejected
    /// before the context is created.
    @Test(arguments: [
        CGSize(width: CGFloat.nan, height: CGFloat.nan),
        CGSize(width: 40, height: CGFloat.nan),
        CGSize(width: CGFloat.nan, height: 40),
        CGSize(width: CGFloat.infinity, height: CGFloat.infinity),
        CGSize(width: 40, height: CGFloat.infinity),
        CGSize(width: -CGFloat.infinity, height: -CGFloat.infinity),
        CGSize(width: 0, height: 0),
        CGSize(width: -40, height: -40)
    ])
    func drawingPrimitivesReturnNilForInvalidTargetSizes(targetSize: CGSize) {
        // Given
        let input = Test.rgbImage(width: 40, height: 40)

        // Then every drawing primitive bails out instead of crashing
        #expect(input.draw(inCanvasWithSize: targetSize) == nil)
        #expect(input.processed.byResizing(to: targetSize, contentMode: .aspectFill, upscale: false) == nil)
        #expect(input.processed.byResizing(to: targetSize, contentMode: .aspectFill, upscale: true) == nil)
        #expect(input.processed.byResizing(to: targetSize, contentMode: .aspectFit, upscale: false) == nil)
        #expect(input.processed.byResizing(to: targetSize, contentMode: .aspectFit, upscale: true) == nil)
        #expect(input.processed.byResizingAndCropping(to: targetSize, upscale: false) == nil)
        #expect(input.processed.byResizingAndCropping(to: targetSize, upscale: true) == nil)
    }

    @Test func drawingReturnsNilForFiniteButOutOfRangeTargetSize() {
        // Given a size that is finite but is way out of the `Int` range
        let input = Test.rgbImage(width: 40, height: 40)
        let targetSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Then
        #expect(input.draw(inCanvasWithSize: targetSize) == nil)
        #expect(input.processed.byResizing(to: targetSize, contentMode: .aspectFill, upscale: true) == nil)
        #expect(input.processed.byResizingAndCropping(to: targetSize, upscale: true) == nil)
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

    // MARK: - Pixel Dimensions

    @Test(arguments: [
        (CGFloat(1), 1),
        (1.9, 1),
        (640, 640),
        (1_073_741_824, 1_073_741_824)
    ])
    func pixelDimensionOfValidValue(value: CGFloat, expected: Int) {
        #expect(value.pixelDimension == expected)
    }

    /// Anything under a pixel is too small to draw in, and the upper bound
    /// keeps the conversion in range on 32-bit platforms.
    @Test(arguments: [CGFloat(0.999), 0, -1, 1_073_741_825, .nan, .infinity, -.infinity])
    func pixelDimensionOfInvalidValue(value: CGFloat) {
        #expect(value.pixelDimension == nil)
    }

    // MARK: - Orientation

    @Test(arguments: [
        (CGImagePropertyOrientation.up, false),
        (.upMirrored, false),
        (.down, false),
        (.downMirrored, false),
        (.left, true),
        (.leftMirrored, true),
        (.right, true),
        (.rightMirrored, true)
    ])
    func sizeIsRotatedForTheOrientationsThatTurnTheImageOnItsSide(orientation: CGImagePropertyOrientation, isRotated: Bool) {
        let size = CGSize(width: 40, height: 30)
        #expect(size.rotatedForOrientation(orientation) == (isRotated ? CGSize(width: 30, height: 40) : size))
    }

#if canImport(UIKit)
    @Test(arguments: [
        UIImage.Orientation.up, .upMirrored, .down, .downMirrored,
        .left, .leftMirrored, .right, .rightMirrored
    ])
    func orientationSurvivesTheRoundTripThroughImageIO(orientation: UIImage.Orientation) {
        #expect(UIImage.Orientation(CGImagePropertyOrientation(orientation)) == orientation)
    }

    @Test func orientationsMapToTheirImageIOCounterparts() {
        #expect(CGImagePropertyOrientation(UIImage.Orientation.up) == .up)
        #expect(CGImagePropertyOrientation(UIImage.Orientation.right) == .right)
        #expect(CGImagePropertyOrientation(UIImage.Orientation.leftMirrored) == .leftMirrored)
        #expect(UIImage.Orientation(CGImagePropertyOrientation.down) == .down)
    }
#endif

    @Test func drawingWithOrientationReturnsNilForInvalidSize() throws {
        // Given
        let cgImage = try #require(Test.rgbImage(width: 40, height: 30).cgImage)

        // Then
        #expect(cgImage.drawn(inCanvasWithSize: .zero, orientation: .up) == nil)
        #expect(cgImage.drawn(inCanvasWithSize: CGSize(width: CGFloat.nan, height: 30), orientation: .right) == nil)
    }

    // MARK: - Pixel Formats

    /// The canvas always has 8 bits per component, and Core Graphics has no
    /// such context for some of the source color spaces, so the drawing has to
    /// fall back to RGB instead of failing.
    ///
    /// - seealso: https://github.com/kean/Nuke/issues/35
    /// - seealso: https://github.com/kean/Nuke/issues/57
    @Test(arguments: GraphicsSourceFormat.allCases)
    func drawingImagesInOtherPixelFormats(format: GraphicsSourceFormat) throws {
        // Given
        let input = try #require(format.makeImage(width: 40, height: 30))

        // When
        let output = try #require(input.draw(inCanvasWithSize: CGSize(width: 20, height: 15)))

        // Then
        let cgImage = try #require(output.cgImage)
        #expect(cgImage.width == 20)
        #expect(cgImage.height == 15)
        #expect(cgImage.colorSpace?.model == format.expectedModel)
        #expect(cgImage.bitsPerComponent == 8)
        #expect(cgImage.isOpaque)
    }
}

/// Source pixel formats other than 8-bit RGB and grayscale.
enum GraphicsSourceFormat: CaseIterable, Sendable {
    case cmyk
    case indexed
    case grayscale16

    /// The color space model of the canvas the image ends up drawn in.
    var expectedModel: CGColorSpaceModel {
        switch self {
        case .cmyk, .indexed: .rgb
        case .grayscale16: .monochrome
        }
    }

    func makeImage(width: Int, height: Int) -> PlatformImage? {
        let cgImage: CGImage?
        switch self {
        case .cmyk:
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceCMYK(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            context?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
            cgImage = context?.makeImage()
        case .grayscale16:
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            context?.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
            cgImage = context?.makeImage()
        case .indexed:
            // A two-color palette, the kind a palette PNG decodes to.
            let palette: [UInt8] = [255, 0, 0, 0, 0, 255]
            guard let space = CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: 1, colorTable: palette) else {
                return nil
            }
            let pixels = Data((0..<(width * height)).map { UInt8($0 % 2) })
            guard let provider = CGDataProvider(data: pixels as CFData) else {
                return nil
            }
            cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }
        return cgImage.map { PlatformImage(cgImage: $0) }
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

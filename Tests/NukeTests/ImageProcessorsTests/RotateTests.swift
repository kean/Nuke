// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Testing
import Foundation
@testable import Nuke

#if canImport(UIKit)
import UIKit
#endif

@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsRotateTests {
    // MARK: Quarter Turns

    @Test func quarterTurnIsClockwiseAndMovesEveryPixelExactly() throws {
        let grid = PixelGrid(width: 5, height: 3)

        let output = try #require(ImageProcessors.Rotate(degrees: 90).process(grid.makeImage()))

        #expect(try PixelGrid(storedPixelsOf: output) == grid.rotatedClockwise)
    }

    @Test func halfTurn() throws {
        let grid = PixelGrid(width: 5, height: 3)

        let output = try #require(ImageProcessors.Rotate(degrees: 180).process(grid.makeImage()))

        #expect(try PixelGrid(storedPixelsOf: output) == grid.rotatedClockwise.rotatedClockwise)
    }

    @Test func threeQuarterTurn() throws {
        let grid = PixelGrid(width: 5, height: 3)

        let output = try #require(ImageProcessors.Rotate(degrees: 270).process(grid.makeImage()))

        #expect(try PixelGrid(storedPixelsOf: output) == grid.rotatedClockwise.rotatedClockwise.rotatedClockwise)
    }

    /// The test for resampling, with translucent pixels included: four turns
    /// of a real photo add up to the bytes that went in.
    @Test(arguments: [
        PixelGrid(width: 7, height: 4, isOpaque: false),
        try! PixelGrid(storedPixelsOf: Test.image(named: "fixture-tiny", extension: "jpeg"))
    ])
    func fourQuarterTurnsRestoreEveryPixel(grid: PixelGrid) throws {
        var image = grid.makeImage()
        for _ in 0..<4 {
            image = try #require(ImageProcessors.Rotate(degrees: 90).process(image))
        }

        #expect(try PixelGrid(storedPixelsOf: image) == grid)
    }

    @Test func wideGamutPixelsAreNotResampled() throws {
        let input = Test.image(named: "image-p3", extension: "jpg")

        var image = input
        for _ in 0..<4 {
            image = try #require(ImageProcessors.Rotate(degrees: 90).process(image))
        }

        #expect(image.cgImage?.colorSpace?.isWideGamutRGB == true)
        #expect(try PixelGrid(storedPixelsOf: image) == PixelGrid(storedPixelsOf: input))
    }

#if canImport(UIKit)
    @Test(arguments: allOrientations, [90, 180, 270] as [CGFloat])
    func quarterTurnsActOnTheDisplayedImage(orientation: UIImage.Orientation, degrees: CGFloat) throws {
        let input = UIImage(cgImage: PixelGrid(width: 5, height: 3).makeCGImage(), scale: 1, orientation: orientation)
        var expected = try PixelGrid(displayedPixelsOf: input)
        for _ in 0..<Int(degrees / 90) {
            expected = expected.rotatedClockwise
        }

        let output = try #require(ImageProcessors.Rotate(degrees: degrees).process(input))

        #expect(output.imageOrientation == .up)
        #expect(try PixelGrid(storedPixelsOf: output) == expected)
    }
#endif

    @Test func decodedPhotoWithOrientation() throws {
        let input = Test.image(named: "right-orientation", extension: "jpeg")
        let displayed = try PixelGrid(displayedPixelsOf: input)

        let output = try #require(ImageProcessors.Rotate(degrees: 90).process(input))

        #expect(try PixelGrid(displayedPixelsOf: output).isClose(to: displayed.rotatedClockwise))
    }

    @Test(arguments: [0, 360, -360, 720] as [CGFloat])
    func fullTurnsReturnTheInput(degrees: CGFloat) {
        let input = PixelGrid(width: 4, height: 3).makeImage()

        #expect(ImageProcessors.Rotate(degrees: degrees).process(input) === input)
    }

    // MARK: Normalization

    @Test(arguments: [(450, 90), (-90, 270), (-450, 270), (360, 0), (-360, 0), (-1e-20, 0)] as [(CGFloat, CGFloat)])
    func anglesAreNormalized(degrees: CGFloat, normalized: CGFloat) {
        let processor = ImageProcessors.Rotate(degrees: degrees)
        let expected = ImageProcessors.Rotate(degrees: normalized)

        #expect(processor == expected)
        #expect(processor.identifier == expected.identifier)
    }

    @Test(arguments: [.nan, .infinity] as [CGFloat])
    func nonFiniteAngleFails(degrees: CGFloat) {
        #expect(ImageProcessors.Rotate(degrees: degrees).process(PixelGrid(width: 4, height: 3).makeImage()) == nil)
    }

    // MARK: Any Angle

    @Test func canvasGrowsToTheBoundingBox() throws {
        let input = Test.rgbImage(width: 100, height: 50)

        let output = try #require(ImageProcessors.Rotate(degrees: 45).process(input))

        // 150 × cos(45°) = 106.07
        let cgImage = try #require(output.cgImage)
        #expect(cgImage.width == 107)
        #expect(cgImage.height == 107)
    }

    @Test func cornersAreTransparentOnAnOpaqueImage() throws {
        let input = Test.rgbImage(width: 100, height: 100)
        #expect(input.cgImage?.isOpaque == true)

        let output = try #require(ImageProcessors.Rotate(degrees: 45).process(input))

        #expect(output.cgImage?.isOpaque == false)
        let pixels = try #require(RGBABitmap(image: output))
        let (width, height) = (pixels.width, pixels.height)
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
            #expect(pixels.alpha(atX: x, y: y) == 0)
        }
        #expect(pixels.alpha(atX: width / 2, y: height / 2) == 255)
    }

    /// The stripes run from left to right, so a clockwise turn brings the first
    /// one up, and the last one down.
    @Test func anyAngleIsClockwise() throws {
        let input = Test.stripedImage(width: 99, height: 99, isVertical: true)
        let stripes = try #require(RGBABitmap(image: input))

        let output = try #require(ImageProcessors.Rotate(degrees: 45).process(input))

        let pixels = try #require(RGBABitmap(image: output))
        let (centerX, centerY) = (pixels.width / 2, pixels.height / 2)
        #expect(pixels.color(atX: centerX, y: centerY - 40).isClose(to: stripes.color(atX: 10, y: 50)))
        #expect(pixels.color(atX: centerX, y: centerY + 40).isClose(to: stripes.color(atX: 90, y: 50)))
    }

    /// The canvas doesn't gain a pixel from the rounding error of `cos` and `sin`.
    @Test func wholeNumberBoxIsNotRoundedUp() throws {
        // 3-4-5 triangle: cos 36.87° = 0.8, sin 36.87° = 0.6, so the box of a
        // 50x50 image is 70x70 to within a tiny error.
        let degrees = atan2(CGFloat(3), 4) * 180 / .pi
        let input = Test.rgbImage(width: 50, height: 50)

        let output = try #require(ImageProcessors.Rotate(degrees: degrees).process(input))

        #expect(output.cgImage?.width == 70)
        #expect(output.cgImage?.height == 70)
    }

    // MARK: Identifiers

    @Test func identifierIsStable() {
        let processor = ImageProcessors.Rotate(degrees: 90)

        #expect(processor.identifier == "com.github.kean/nuke/rotate?degrees=90.0")
        #expect(processor.description == "Rotate(degrees: 90.0)")
    }

    @Test func everyParameterChangesTheIdentifiers() {
        let processor = ImageProcessors.Rotate(degrees: 90)
        let other = ImageProcessors.Rotate(degrees: 91)

        #expect(processor.identifier != other.identifier)
        #expect(processor.hashableIdentifier != other.hashableIdentifier)
        #expect(processor.hashableIdentifier == ImageProcessors.Rotate(degrees: 450).hashableIdentifier)
    }
}

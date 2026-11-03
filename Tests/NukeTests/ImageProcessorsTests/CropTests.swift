// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

#if canImport(UIKit)
import UIKit
#endif

@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsCropTests {
    private func crop(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> ImageProcessors.Crop {
        ImageProcessors.Crop(rect: CGRect(x: x, y: y, width: width, height: height), unit: .pixels)
    }

    @Test func rectIsMeasuredFromTheTopLeft() throws {
        let grid = PixelGrid(width: 5, height: 4)

        let output = try #require(crop(1, 1, 3, 2).process(grid.makeImage()))

        #expect(try PixelGrid(storedPixelsOf: output) == grid.cropped(x: 1, y: 1, width: 3, height: 2))
    }

    /// A translucent image has to come out the same, since the crop draws it.
    @Test func alphaIsKept() throws {
        let grid = PixelGrid(width: 4, height: 3, isOpaque: false)

        let output = try #require(crop(1, 0, 2, 2).process(grid.makeImage()))

        #expect(try PixelGrid(storedPixelsOf: output) == grid.cropped(x: 1, y: 0, width: 2, height: 2))
    }

#if canImport(UIKit)
    @Test(arguments: allOrientations)
    func rectIsMeasuredOnTheDisplayedImage(orientation: UIImage.Orientation) throws {
        let input = UIImage(cgImage: PixelGrid(width: 5, height: 3).makeCGImage(), scale: 1, orientation: orientation)
        let displayed = try PixelGrid(displayedPixelsOf: input)

        let output = try #require(crop(1, 1, 2, 2).process(input))

        #expect(output.imageOrientation == .up)
        #expect(try PixelGrid(storedPixelsOf: output) == displayed.cropped(x: 1, y: 1, width: 2, height: 2))
        #expect(try PixelGrid(displayedPixelsOf: output) == displayed.cropped(x: 1, y: 1, width: 2, height: 2))
    }
#endif

    /// The pixels of this file are stored on their side, with an EXIF
    /// orientation that puts them right.
    @Test func decodedPhotoWithOrientation() throws {
        let input = Test.image(named: "right-orientation", extension: "jpeg")
        let displayed = try PixelGrid(displayedPixelsOf: input)

        let output = try #require(crop(20, 10, 100, 60).process(input))

        let expected = displayed.cropped(x: 20, y: 10, width: 100, height: 60)
        #expect(try PixelGrid(displayedPixelsOf: output).isClose(to: expected))
    }

    @Test func rectIsClampedToTheImage() throws {
        let grid = PixelGrid(width: 4, height: 4)

        let output = try #require(crop(2, -1, 10, 3).process(grid.makeImage()))

        #expect(try PixelGrid(storedPixelsOf: output) == grid.cropped(x: 2, y: 0, width: 2, height: 2))
    }

    @Test func negativeSizeIsTheSameRect() {
        #expect(crop(3, 3, -2, -2) == crop(1, 1, 2, 2))
    }

    @Test(arguments: [
        CGRect(x: 10, y: 10, width: 5, height: 5), // Outside
        CGRect(x: 4, y: 0, width: 5, height: 4), // Only touches the edge
        CGRect(x: 1, y: 1, width: 0, height: 2), // Empty
        CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
        CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 1),
        CGRect.null
    ])
    func rectWithNoPixelsFails(rect: CGRect) {
        let input = PixelGrid(width: 4, height: 4).makeImage()

        #expect(ImageProcessors.Crop(rect: rect, unit: .pixels).process(input) == nil)
    }

    @Test func fractionalRectIsRoundedOut() throws {
        let grid = PixelGrid(width: 5, height: 5)

        let output = try #require(crop(1.5, 1.5, 1, 1).process(grid.makeImage()))

        #expect(try PixelGrid(storedPixelsOf: output) == grid.cropped(x: 1, y: 1, width: 2, height: 2))
    }

    /// Nothing changes, so there is nothing to draw, and an image the pipeline
    /// still has to decompress stays the one it knows about.
    @Test func rectOfTheWholeImageReturnsTheInput() throws {
        let input = PixelGrid(width: 4, height: 3).makeImage()

        #expect(crop(0, 0, 4, 3).process(input) === input)
        #expect(crop(-5, -5, 20, 20).process(input) === input)
    }

    /// On a decoded image, `CGImage.cropping(to:)` keeps the row bytes of the
    /// input, and the whole input with them, which the memory cache wouldn't
    /// charge for.
    @Test func outputOwnsItsPixels() throws {
        let input = Test.rgbImage(width: 640, height: 480)

        let output = try #require(crop(0, 0, 10, 10).process(input))

        let cgImage = try #require(output.cgImage)
        #expect(cgImage.bytesPerRow < 128)
    }

    @Test @MainActor func pointsAreConvertedWithTheScreenScale() {
        let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let scale = Screen.scale
        let pixels = CGRect(x: scale, y: 2 * scale, width: 3 * scale, height: 4 * scale)

        let points = ImageProcessors.Crop(rect: rect)

        #expect(points == ImageProcessors.Crop(rect: pixels, unit: .pixels))
        #expect(points.identifier == ImageProcessors.Crop(rect: pixels, unit: .pixels).identifier)
    }

#if canImport(UIKit)
    /// `.points` are the points of the screen, as in `Resize`, whatever the
    /// scale of the image: the rect is the same number of pixels on a @3x one.
    @Test @MainActor func pointsOnAnImageOfAnotherScale() throws {
        let scale = Int(Screen.scale)
        let grid = PixelGrid(width: 5 * scale, height: 5 * scale)
        let input = UIImage(cgImage: grid.makeCGImage(), scale: 3, orientation: .up)

        let output = try #require(ImageProcessors.Crop(rect: CGRect(x: 1, y: 1, width: 2, height: 2)).process(input))

        #expect(output.scale == 3)
        #expect(try PixelGrid(storedPixelsOf: output) == grid.cropped(x: scale, y: scale, width: 2 * scale, height: 2 * scale))
    }
#endif

    @Test func identifierIsStable() {
        let processor = crop(1, 2, 3, 4)

        // Part of the disk cache keys: changing it invalidates what's stored.
        #expect(processor.identifier == "com.github.kean/nuke/crop?x=1.0,y=2.0,width=3.0,height=4.0")
        #expect(processor.description == "Crop(rect: (1.0, 2.0, 3.0, 4.0) pixels)")
    }

    @Test(arguments: [
        CGRect(x: 9, y: 2, width: 3, height: 4),
        CGRect(x: 1, y: 9, width: 3, height: 4),
        CGRect(x: 1, y: 2, width: 9, height: 4),
        CGRect(x: 1, y: 2, width: 3, height: 9)
    ])
    func everyParameterChangesTheIdentifiers(rect: CGRect) {
        let processor = crop(1, 2, 3, 4)
        let other = ImageProcessors.Crop(rect: rect, unit: .pixels)

        #expect(processor.identifier != other.identifier)
        #expect(processor.hashableIdentifier != other.hashableIdentifier)
    }

    @Test func equalProcessorsHaveEqualIdentifiers() {
        #expect(crop(1, 2, 3, 4).hashableIdentifier == crop(1, 2, 3, 4).hashableIdentifier)
    }
}

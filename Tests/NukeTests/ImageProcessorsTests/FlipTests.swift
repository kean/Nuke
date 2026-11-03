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
struct ImageProcessorsFlipTests {
    @Test func horizontalSwapsLeftAndRight() throws {
        let grid = PixelGrid(width: 5, height: 3)

        let output = try #require(ImageProcessors.Flip(.horizontal).process(grid.makeImage()))

        #expect(try PixelGrid(storedPixelsOf: output) == grid.flippedHorizontally)
    }

    @Test func verticalSwapsTopAndBottom() throws {
        let grid = PixelGrid(width: 5, height: 3)

        let output = try #require(ImageProcessors.Flip(.vertical).process(grid.makeImage()))

        #expect(try PixelGrid(storedPixelsOf: output) == grid.flippedVertically)
    }

    @Test(arguments: [ImageProcessors.Flip.Direction.horizontal, .vertical])
    func flippingTwiceRestoresEveryPixel(direction: ImageProcessors.Flip.Direction) throws {
        let grid = PixelGrid(width: 4, height: 3, isOpaque: false)
        let processor = ImageProcessors.Flip(direction)

        let once = try #require(processor.process(grid.makeImage()))
        let twice = try #require(processor.process(once))

        #expect(try PixelGrid(storedPixelsOf: twice) == grid)
    }

#if canImport(UIKit)
    @Test(arguments: allOrientations)
    func horizontalActsOnTheDisplayedImage(orientation: UIImage.Orientation) throws {
        let input = UIImage(cgImage: PixelGrid(width: 5, height: 3).makeCGImage(), scale: 1, orientation: orientation)
        let displayed = try PixelGrid(displayedPixelsOf: input)

        let output = try #require(ImageProcessors.Flip(.horizontal).process(input))

        #expect(output.imageOrientation == .up)
        #expect(try PixelGrid(storedPixelsOf: output) == displayed.flippedHorizontally)
    }

    @Test(arguments: allOrientations)
    func verticalActsOnTheDisplayedImage(orientation: UIImage.Orientation) throws {
        let input = UIImage(cgImage: PixelGrid(width: 5, height: 3).makeCGImage(), scale: 1, orientation: orientation)
        let displayed = try PixelGrid(displayedPixelsOf: input)

        let output = try #require(ImageProcessors.Flip(.vertical).process(input))

        #expect(output.imageOrientation == .up)
        #expect(try PixelGrid(storedPixelsOf: output) == displayed.flippedVertically)
    }
#endif

    @Test func decodedPhotoWithOrientation() throws {
        let input = Test.image(named: "right-orientation", extension: "jpeg")
        let displayed = try PixelGrid(displayedPixelsOf: input)

        let output = try #require(ImageProcessors.Flip(.horizontal).process(input))

        #expect(try PixelGrid(displayedPixelsOf: output).isClose(to: displayed.flippedHorizontally))
    }

    @Test func identifierIsStable() {
        let processor = ImageProcessors.Flip(.horizontal)

        #expect(processor.identifier == "com.github.kean/nuke/flip?direction=horizontal")
        #expect(ImageProcessors.Flip(.vertical).identifier == "com.github.kean/nuke/flip?direction=vertical")
        #expect(processor.description == "Flip(direction: horizontal)")
    }

    @Test func everyParameterChangesTheIdentifiers() {
        let horizontal = ImageProcessors.Flip(.horizontal)
        let vertical = ImageProcessors.Flip(.vertical)

        #expect(horizontal.hashableIdentifier != vertical.hashableIdentifier)
        #expect(horizontal.hashableIdentifier == ImageProcessors.Flip(.horizontal).hashableIdentifier)
    }
}

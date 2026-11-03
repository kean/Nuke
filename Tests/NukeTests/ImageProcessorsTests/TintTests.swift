// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Testing
import Foundation
@testable import Nuke

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsTintTests {
    private static let red = PlatformColor(red: 1, green: 0, blue: 0, alpha: 1)

    /// `sourceAtop` with an opaque color: every pixel is the color at the alpha
    /// it had, premultiplied.
    @Test func opaqueColorMakesASilhouette() throws {
        let grid = PixelGrid(width: 4, height: 3, isOpaque: false)

        let output = try #require(ImageProcessors.Tint(color: Self.red).process(grid.makeImage()))

        let pixels = try #require(RGBABitmap(image: output))
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let alpha = try #require(grid.pixel(x: x, y: y).last)
                #expect(pixels.pixel(atX: x, y: y) == [alpha, 0, 0, alpha])
            }
        }
    }

    @Test func translucentColorIsLaidOverTheImage() throws {
        let input = Test.rgbImage(width: 4, height: 4, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let color = PlatformColor(red: 1, green: 0, blue: 0, alpha: 0.5)

        let output = try #require(ImageProcessors.Tint(color: color).process(input))

        // Halfway between the image and the color, whatever the components of
        // the two come to in this color space on this platform.
        let image = try pixelComponents(of: input, x: 1, y: 1)
        let tint = try pixelComponents(of: try #require(ImageProcessors.Tint(color: Self.red).process(input)), x: 1, y: 1)
        let pixel = try pixelComponents(of: output, x: 1, y: 1)
        for component in 0..<3 {
            #expect(abs(Int(pixel[component]) - (Int(image[component]) + Int(tint[component])) / 2) <= 1)
        }
        #expect(pixel[3] == 255)
    }

    @Test func clearColorLeavesTheImageAsItIs() throws {
        let grid = PixelGrid(width: 4, height: 3, isOpaque: false)

        let output = try #require(ImageProcessors.Tint(color: PlatformColor(white: 0, alpha: 0)).process(grid.makeImage()))

        #expect(try PixelGrid(storedPixelsOf: output) == grid)
    }

    @Test func transparentPixelsStayTransparent() throws {
        let input = Test.imageWithOpaqueSquare(size: 20, square: 10)

        let output = try #require(ImageProcessors.Tint(color: Self.red).process(input))

        let pixels = try #require(RGBABitmap(image: output))
        #expect(pixels.pixel(atX: 1, y: 1) == [0, 0, 0, 0])
        #expect(pixels.pixel(atX: 10, y: 10) == [255, 0, 0, 255])
    }

    /// The color would come out gray in a context of the image's color space.
    @Test func monochromeImageTakesTheColor() throws {
        let input = Test.grayscaleImage(width: 4, height: 4)

        let output = try #require(ImageProcessors.Tint(color: Self.red).process(input))

        #expect(output.cgImage?.isOpaque == true)
        #expect(try pixelComponents(of: output, x: 1, y: 1) == [255, 0, 0, 255])
    }

    @Test func decodedMonochromeImageTakesTheColor() throws {
        let input = Test.image(named: "grayscale", extension: "jpeg")

        let output = try #require(ImageProcessors.Tint(color: Self.red).process(input))

        #expect(try pixelComponents(of: output, x: 10, y: 10) == [255, 0, 0, 255])
    }

    @Test func monochromeImageWithAlphaTakesTheColorAndKeepsItsAlpha() throws {
        let input = Test.grayscaleWithAlphaImage(width: 4, height: 4, gray: 100, alpha: 128)

        let output = try #require(ImageProcessors.Tint(color: Self.red).process(input))

        #expect(output.cgImage?.isOpaque == false)
        #expect(try pixelComponents(of: output, x: 1, y: 1) == [128, 0, 0, 128])
    }

    @Test func wideGamutIsKept() throws {
        let input = Test.image(named: "image-p3", extension: "jpg")

        let output = try #require(ImageProcessors.Tint(color: PlatformColor(white: 0, alpha: 0.2)).process(input))

        #expect(output.cgImage?.colorSpace?.isWideGamutRGB == true)
    }

#if canImport(UIKit)
    /// Nothing about the tint depends on which way up the image is, so the
    /// stored pixels and their orientation stay as they were.
    @Test(arguments: allOrientations)
    func orientationIsKept(orientation: UIImage.Orientation) throws {
        let grid = PixelGrid(width: 5, height: 3, isOpaque: false)
        let input = UIImage(cgImage: grid.makeCGImage(), scale: 2, orientation: orientation)

        let output = try #require(ImageProcessors.Tint(color: PlatformColor(white: 0, alpha: 0)).process(input))

        #expect(output.imageOrientation == orientation)
        #expect(output.scale == 2)
        #expect(try PixelGrid(storedPixelsOf: output) == grid)
    }
#endif

    @Test func identifierIsStable() {
        let processor = ImageProcessors.Tint(color: Self.red)

        #expect(processor.identifier == "com.github.kean/nuke/tint?color=#FF0000")
        #expect(processor.description == "Tint(color: #FF0000)")
    }

    @Test func translucentColorIsPartOfTheIdentifier() {
        let color = PlatformColor(red: 1, green: 0, blue: 0, alpha: 0.5)

        #expect(ImageProcessors.Tint(color: color).identifier == "com.github.kean/nuke/tint?color=#FF000080")
    }

    /// On AppKit, `.black` isn't in an RGB color space, which `hex` converts it to.
    @Test func colorOutsideOfRGBHasAStableIdentifier() {
        #expect(ImageProcessors.Tint(color: .black).identifier == "com.github.kean/nuke/tint?color=#000000")
    }

    @Test func everyParameterChangesTheIdentifiers() {
        let processor = ImageProcessors.Tint(color: Self.red)
        let other = ImageProcessors.Tint(color: PlatformColor(red: 0, green: 1, blue: 0, alpha: 1))

        #expect(processor.identifier != other.identifier)
        #expect(processor.hashableIdentifier != other.hashableIdentifier)
        #expect(processor.hashableIdentifier == ImageProcessors.Tint(color: Self.red).hashableIdentifier)
    }
}

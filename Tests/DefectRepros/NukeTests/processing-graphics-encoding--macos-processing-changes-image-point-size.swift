// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import Nuke

// BUG (macOS): the processors that keep the pixel size of an image –
// `GaussianBlur`, `CoreImageFilter`, `RoundedCorners` – change its point size
// when the image's point size isn't its pixel size.
//
// `NSImage.make(cgImage:source:)` ignores `source` and creates the output with
// `NSImage(cgImage:size: .zero)`, i.e. one point per pixel. Its UIKit
// counterpart preserves `source.scale` and `source.imageOrientation`. On
// macOS, `ImageDecoders.Default` decodes with `NSImage(data:)`, which sizes an
// image by its DPI: a 144-DPI PNG or JPEG – what a Retina Mac writes for a
// screenshot – decodes to half its pixel size in points. Blur it, and it is
// displayed twice as large as the unprocessed image.
//
// Expected: a 40x40 px image decoded at 20x20 pt is still 20x20 pt after a
// blur, as it is on iOS for `UIImage.scale`.
// Actual: 40x40 pt.
//
// Sources/Nuke/Internal/Graphics.swift:323-325
#if os(macOS)
import AppKit

@Suite(.timeLimit(.minutes(5)))
struct MacOSProcessedImagePointSizeBugRepro {
    @Test func blurPreservesThePointSizeOfA144DPIImage() throws {
        // GIVEN a 40x40 px PNG saved at 144 DPI, decoded by the default decoder
        let data = try makePNG(width: 40, height: 40, dpi: 144)
        let input = try ImageDecoders.Default().decode(data).image
        #expect(input.size == CGSize(width: 20, height: 20))

        // WHEN
        let output = try #require(ImageProcessors.GaussianBlur(radius: 2).process(input))

        // THEN
        #expect(output.size == input.size) // Actual: (40.0, 40.0)
    }

    @Test(arguments: [0, 1, 2])
    func sizePreservingProcessorsKeepThePointSize(index: Int) throws {
        // GIVEN a 40x40 px image with a size of 20x20 pt
        let cgImage = try #require(Test.rgbImage(width: 40, height: 40).cgImage)
        let input = NSImage(cgImage: cgImage, size: NSSize(width: 20, height: 20))
        let processor: any ImageProcessing = [
            ImageProcessors.GaussianBlur(radius: 2) as any ImageProcessing,
            ImageProcessors.CoreImageFilter(name: "CISepiaTone"),
            ImageProcessors.RoundedCorners(radius: 4, unit: .pixels)
        ][index]

        // WHEN
        let output = try #require(processor.process(input))

        // THEN
        #expect(output.size == CGSize(width: 20, height: 20)) // Actual: (40.0, 40.0)
    }

    private func makePNG(width: Int, height: Int, dpi: Int) throws -> Data {
        let cgImage = try #require(Test.rgbImage(width: width, height: height).cgImage)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, AssetType.png.rawValue as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
#endif

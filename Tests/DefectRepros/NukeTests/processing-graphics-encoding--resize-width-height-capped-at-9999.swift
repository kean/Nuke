// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

// BUG: `ImageProcessors.Resize(width:)` and `Resize(height:)` – and the
// `.resize(width:)`/`.resize(height:)` shorthands – cap the other dimension at
// 9999 (in the unit given, so 9999 px with `.pixels` and on macOS).
//
// `init(width:)` is implemented as `.aspectFit` into `(width, 9999)`, so for
// an image whose height at the requested width would exceed 9999, the height
// becomes the limiting dimension: the image is scaled below the requested
// width. It even downscales an image that is already narrower than the
// requested width and shouldn't be touched at all (`upscale` is `false`).
// Tall images – long screenshots, webtoon strips, infographics – and wide
// panoramas with `Resize(height:)` are affected.
//
// Expected (per the docs, "Scales an image to the given width preserving
// aspect ratio"): a 10x30000 image resized to a width of 5 is 5x15000, and a
// 100x20000 image resized to a width of 200 is left as is.
// Actual: 3x9999 and 50x9999.
//
// Sources/Nuke/Processing/ImageProcessors+Resize.swift:45 and :55
@Suite(.timeLimit(.minutes(5)))
struct ResizeDimensionCapBugRepro {
    @Test func resizeToWidthOfTallImage() throws {
        // GIVEN a 10x30000 image
        let input = makeImage(width: 10, height: 30_000)

        // WHEN
        let output = try #require(ImageProcessors.Resize(width: 5, unit: .pixels).process(input))

        // THEN
        #expect(output.cgImage?.width == 5) // Actual: 3
        #expect(output.cgImage?.height == 15_000) // Actual: 9999
    }

    @Test func resizeToHeightOfWideImage() throws {
        // GIVEN a 30000x10 image
        let input = makeImage(width: 30_000, height: 10)

        // WHEN
        let output = try #require(ImageProcessors.Resize(height: 5, unit: .pixels).process(input))

        // THEN
        #expect(output.cgImage?.width == 15_000) // Actual: 9999
        #expect(output.cgImage?.height == 5) // Actual: 3
    }

    @Test func resizeToWidthLeavesNarrowerTallImageAlone() throws {
        // GIVEN a 100x20000 image, narrower than the target width
        let input = makeImage(width: 100, height: 20_000)

        // WHEN
        let output = try #require(ImageProcessors.Resize(width: 200, unit: .pixels).process(input))

        // THEN there is nothing to do without upscaling
        #expect(output === input) // Actual: downscaled to 50x9999
    }

    private func makeImage(width: Int, height: Int) -> PlatformImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return PlatformImage(cgImage: context.makeImage()!)
    }
}

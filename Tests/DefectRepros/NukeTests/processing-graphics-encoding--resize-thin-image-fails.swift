// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

// BUG: downscaling a thin image – a separator, a progress bar, a gradient
// strip – with `.aspectFit` (which includes `Resize(width:)` and
// `Resize(height:)`) fails instead of producing a one-pixel-thin image.
//
// `byResizing(to:contentMode:upscale:)` rounds the scaled size, and a side
// that scales below half a pixel rounds to `0`, which the `pixelDimension`
// guard (added for #888) rejects. `process` returns `nil`, and the pipeline
// fails the request with `processingFailed`. The image can be represented –
// Image I/O's own downsampling (`ImageRequest.ThumbnailOptions`) returns a
// 100x1 image for the same input and target.
//
// Expected: a 1000x2 image fitted into 100x100 is 100x1.
// Actual: `nil`.
//
// Sources/Nuke/Internal/Graphics.swift:47
@Suite(.timeLimit(.minutes(5)))
struct ResizeThinImageBugRepro {
    @Test func fittingThinImageProducesAOnePixelThinImage() throws {
        // GIVEN a 1000x2 image
        let input = makeImage(width: 1000, height: 2)

        // WHEN
        let output = ImageProcessors.Resize(size: CGSize(width: 100, height: 100), unit: .pixels, contentMode: .aspectFit).process(input)

        // THEN
        let cgImage = try #require(output?.cgImage) // Actual: nil
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 1)
    }

    @Test func resizingThinImageToWidth() throws {
        // GIVEN a 1000x2 image
        let input = makeImage(width: 1000, height: 2)

        // WHEN
        let output = ImageProcessors.Resize(width: 100, unit: .pixels).process(input)

        // THEN
        let cgImage = try #require(output?.cgImage) // Actual: nil
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 1)
    }

    @Test func thumbnailOfTheSameImageSucceeds() throws {
        // For comparison: Image I/O downsamples the same image just fine
        let data = try #require(ImageEncoders.ImageIO(type: .png).encode(makeImage(width: 1000, height: 2)))
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 100, height: 100), unit: .pixels, contentMode: .aspectFit)

        let thumbnail = try #require(options.makeThumbnail(with: data)?.cgImage)
        #expect(thumbnail.width == 100)
        #expect(thumbnail.height == 1)
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

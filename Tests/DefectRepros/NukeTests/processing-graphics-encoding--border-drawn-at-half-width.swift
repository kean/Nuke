// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

// BUG: the border of `ImageProcessors.RoundedCorners` and
// `ImageProcessors.Circle` is drawn at half the requested width.
//
// `byAddingRoundedCorners(radius:border:)` clips the context to the
// rounded-rect path and then strokes the same path with
// `setLineWidth(border.width)`. A stroke is centered on its path, so the outer
// half of it falls outside the clip and is discarded: a 6 px border comes out
// 3 px wide, a 1 pt default border half a point. `Border.width` is documented
// as "Border width", and the processors report it in their descriptions and
// identifiers ("Border(color: #FF0000, width: 6.0 pixels)").
//
// Expected: the 6 rows of pixels along the top edge are the border color.
// Actual: only the first 3 are. (The reference snapshot
// `s-rounded-corners-border.png` of the disabled snapshot test, generated from
// the implementation, shows the same 2 px border for a requested 4 px.)
// A fix could inset the stroked path by `width / 2` or double the line width.
//
// Sources/Nuke/Internal/Graphics.swift:123-127
@Suite(.timeLimit(.minutes(5)))
struct BorderWidthBugRepro {
    @Test func borderIsAsWideAsRequested() throws {
        // GIVEN a blue image and a 6 px red border
        let input = Test.rgbImage(width: 40, height: 40, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let border = ImageProcessingOptions.Border(color: .red, width: 6, unit: .pixels)

        // WHEN
        let output = try #require(ImageProcessors.RoundedCorners(radius: 1, unit: .pixels, border: border).process(input))

        // THEN the top 6 rows in the middle of the image are red
        let rows = try redChannel(ofColumn: 20, in: output).prefix(8)
        #expect(Array(rows.prefix(6)).allSatisfy { $0 > 200 }, "\(Array(rows))") // Actual: [255, 255, 255, 4, 4, 4, …]
        #expect(Array(rows.suffix(2)).allSatisfy { $0 < 50 }, "\(Array(rows))")
    }

    /// Returns the red component of every pixel in the column, top to bottom.
    private func redChannel(ofColumn x: Int, in image: PlatformImage) throws -> [UInt8] {
        let cgImage = try #require(image.cgImage)
        let (width, height) = (cgImage.width, cgImage.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let isDrawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(isDrawn)
        return (0..<height).map { bytes[($0 * width + x) * 4] }
    }
}

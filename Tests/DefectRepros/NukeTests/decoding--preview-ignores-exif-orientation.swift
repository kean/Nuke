// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Nuke

#if canImport(UIKit)
import UIKit
#endif

// SUSPECTED BUG: `ImageDecoders.Default` builds every preview it produces
// from partially downloaded data – incremental, the `.thumbnail` policy, and
// the thumbnail fallback – with `_make(_:scale:)`, which wraps the `CGImage`
// with `orientation: .up` on UIKit and as-is on AppKit. The EXIF orientation
// the data declares is dropped. The final image is decoded with
// `UIImage(data:)` / `NSImage(data:)`, which apply it.
//
// Expected: a preview is displayed the same way up as the final image that
// replaces it (`Sources/Nuke/Decoding/ImageDecoders+Default.swift:209-215`).
// Before the switch to `CGImageSourceCreateIncremental` (ed89f39c) previews
// were decoded with `UIImage(data:scale:)` and kept the orientation.
//
// Actual: for a JPEG stored as 400×300 with orientation 6 (`.right`), the
// final image is 300×400 (portrait) and every preview is 400×300 (lying on
// its side), so the image snaps a quarter turn when the download completes.
// A progressive JPEG gets the `.incremental` policy by default, so this is
// what `isProgressiveDecodingEnabled = true` shows for any rotated progressive
// JPEG; the `.thumbnail` policy does the same for any rotated camera JPEG.
//
// Target: NukeTests. Fails on macOS and iOS.
@Suite(.timeLimit(.minutes(5)))
struct DecodingPreviewOrientationBugTests {
    @Test func incrementalPreviewHasTheOrientationOfTheFinalImage() throws {
        let data = makeRotatedJPEG(isProgressive: true)
        #expect(ImagePipeline.PreviewPolicy.default(for: data) == .incremental)
        let context = ImageDecodingContext(request: ImageRequest(url: URL(string: "https://example.com/a.jpg")), data: data, isCompleted: false, previewPolicy: .default(for: data))
        let decoder = try #require(ImageDecoders.Default(context: context))

        let preview = try #require(decoder.decodePartiallyDownloadedData(data.prefix(data.count * 3 / 4)))
        let final = try decoder.decode(data)

        #expect(final.image.size == CGSize(width: 300, height: 400))
        #expect(preview.image.size == final.image.size) // Actual: 400×300
    }

    @Test func thumbnailPolicyPreviewHasTheOrientationOfTheFinalImage() throws {
        let data = makeRotatedJPEG(isProgressive: false)
        let context = ImageDecodingContext(request: ImageRequest(url: URL(string: "https://example.com/a.jpg")), data: data, isCompleted: false, previewPolicy: .thumbnail)
        let decoder = try #require(ImageDecoders.Default(context: context))

        let preview = try #require(decoder.decodePartiallyDownloadedData(data.prefix(data.count * 3 / 4)))
        let final = try decoder.decode(data)

        #expect(final.image.size == CGSize(width: 300, height: 400))
        #expect(preview.image.size == final.image.size) // Actual: 400×300
    }

    /// A 400×300 JPEG declaring orientation 6: displayed as 300×400.
    private func makeRotatedJPEG(isProgressive: Bool) -> Data {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [
            kCGImagePropertyOrientation: CGImagePropertyOrientation.right.rawValue,
            kCGImageDestinationEmbedThumbnail: true
        ]
        if isProgressive {
            properties[kCGImagePropertyJFIFDictionary] = [kCGImagePropertyJFIFIsProgressive: true]
        }
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}

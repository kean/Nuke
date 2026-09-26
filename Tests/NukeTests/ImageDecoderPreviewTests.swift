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

/// The previews ``ImageDecoders/Default`` produces from partially downloaded
/// data: which path produces them, how they are numbered, and what a failed
/// attempt leaves behind.
@Suite(.timeLimit(.minutes(5)))
struct ImageDecoderPreviewTests {

    // MARK: Thumbnail Fallback

    @Test func fallsBackToAThumbnailWhileIncrementalDecodingCantReadTheDimensions() throws {
        // The fixture has a ~7 KB EXIF preamble with SOF2 at offset 7394. Past
        // the embedded thumbnail and short of SOF2, the incremental source has
        // no dimensions yet, while a regular source can already make a
        // thumbnail – the case the fallback exists for.
        let data = Test.data(name: "tricky_progressive", extension: "jpeg")
        let decoder = ImageDecoders.Default()

        // Not even the fallback can produce anything from the first 2 KB, and
        // a failed attempt must not use up the one fallback the decoder has.
        #expect(decoder.decodePartiallyDownloadedData(data[0..<2000]) == nil)
        #expect(decoder.numberOfScans == 0)

        // When
        let preview = try #require(decoder.decodePartiallyDownloadedData(data[0..<6000]))

        // Then
        #expect(preview.isPreview)
        #expect(preview.type == .jpeg)
        #expect(preview.userInfo[.scanNumberKey] as? Int == 1)
        #expect(max(preview.image.sizeInPixels.width, preview.image.sizeInPixels.height) <= 160)
        #expect(decoder.numberOfScans == 1)
    }

    @Test func thumbnailFallbackIsUsedOnlyOnce() throws {
        let data = Test.data(name: "tricky_progressive", extension: "jpeg")
        let decoder = ImageDecoders.Default()
        #expect(decoder.decodePartiallyDownloadedData(data[0..<6000]) != nil)

        // More data, still short of the dimensions: the same thumbnail again
        // would be a wasted decode and a preview that looks like no progress.
        #expect(decoder.decodePartiallyDownloadedData(data[0..<7000]) == nil)
        #expect(decoder.numberOfScans == 1)

        // Once Image I/O can read the frame, full-size previews take over and
        // continue the numbering the fallback started.
        let scan = try #require(decoder.decodePartiallyDownloadedData(data[0..<20000]))
        #expect(scan.image.sizeInPixels == CGSize(width: 450, height: 300))
        #expect(scan.userInfo[.scanNumberKey] as? Int == 2)
    }

    // MARK: Numbering

    @Test func finalImageCarriesTheNumberOfPreviewsThatPrecededIt() throws {
        // Documented on `scanNumberKey`: the default decoder attaches it to the
        // final image too, as the total number of previews.
        let data = Test.data(name: "progressive", extension: "jpeg")
        let decoder = ImageDecoders.Default()
        for count in [1000, 5000, 20000] {
            _ = try #require(decoder.decodePartiallyDownloadedData(data[0..<count]))
        }

        let container = try decoder.decode(data)

        #expect(!container.isPreview)
        #expect(container.userInfo[.scanNumberKey] as? Int == 3)
    }

    @Test func previewsFromDifferentDecodersAreNumberedIndependently() throws {
        // A decoder is one decoding session: the count must not leak between
        // them, or the second download of an image would start at scan 4.
        let data = Test.data(name: "progressive", extension: "jpeg")
        let first = ImageDecoders.Default()
        _ = first.decodePartiallyDownloadedData(data[0..<1000])
        _ = first.decodePartiallyDownloadedData(data[0..<5000])

        let second = ImageDecoders.Default()
        let preview = try #require(second.decodePartiallyDownloadedData(data[0..<1000]))

        #expect(preview.userInfo[.scanNumberKey] as? Int == 1)
        #expect(try second.decode(data).userInfo[.scanNumberKey] as? Int == 1)
    }

    // MARK: Thumbnail Policy

    @Test func thumbnailPolicyWaitsForTheThumbnailThenStops() throws {
        let data = Test.data(name: "progressive", extension: "jpeg")
        let context = ImageDecodingContext(request: Test.request, data: data, isCompleted: false, previewPolicy: .thumbnail)
        let decoder = try #require(ImageDecoders.Default(context: context))

        // Too early for a thumbnail: nothing, and nothing counted, so the next
        // chunk gets to try again.
        #expect(decoder.decodePartiallyDownloadedData(data[0..<300]) == nil)
        #expect(decoder.numberOfScans == 0)

        // When
        let preview = try #require(decoder.decodePartiallyDownloadedData(data[0..<2000]))

        // Then
        #expect(preview.isPreview)
        #expect(preview.type == .jpeg)
        #expect(preview.userInfo[.scanNumberKey] as? Int == 1)

        // Only one, however much more data arrives
        #expect(decoder.decodePartiallyDownloadedData(data[0..<20000]) == nil)
        #expect(decoder.decodePartiallyDownloadedData(data) == nil)
        #expect(try decoder.decode(data).userInfo[.scanNumberKey] as? Int == 1)
    }

    // MARK: Thumbnail Request

    @Test func previewsOfAThumbnailRequestAreThumbnails() throws {
        // A thumbnail request asks for a small image to save memory; a preview
        // decoded at the full size of the image would undo that, and it can
        // land in the memory cache under the thumbnail's key.
        let data = Test.data(name: "progressive", extension: "jpeg")
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 64)
        let context = ImageDecodingContext(request: request, data: data, isCompleted: false, previewPolicy: .default(for: data))
        #expect(context.previewPolicy == .incremental)
        let decoder = try #require(ImageDecoders.Default(context: context))

        let preview = try #require(decoder.decodePartiallyDownloadedData(data[0..<20000]))
        let final = try decoder.decode(data)

        #expect(preview.isPreview)
        #expect(preview.userInfo[.scanNumberKey] as? Int == 1)
        #expect(final.image.sizeInPixels == CGSize(width: 64, height: 43))
        #expect(preview.image.sizeInPixels == final.image.sizeInPixels)
    }

    @Test func thumbnailFallbackOfAThumbnailRequestIsNoLargerThanTheThumbnail() throws {
        let data = Test.data(name: "tricky_progressive", extension: "jpeg")
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 64)
        let context = ImageDecodingContext(request: request, data: data, isCompleted: false, previewPolicy: .incremental)
        let decoder = try #require(ImageDecoders.Default(context: context))

        let preview = try #require(decoder.decodePartiallyDownloadedData(data[0..<6000]))

        #expect(max(preview.image.sizeInPixels.width, preview.image.sizeInPixels.height) <= 64)
        #expect(decoder.numberOfScans == 1)
    }

    // MARK: Orientation

    @Test func incrementalPreviewIsDisplayedWithTheOrientationOfTheFinalImage() throws {
        // The final image comes from `UIImage(data:)` / `NSImage(data:)`, which
        // apply the EXIF orientation. A preview that didn't would lie on its
        // side until the download completes, then snap a quarter turn.
        let data = makeRotatedJPEG(isProgressive: true)
        let context = ImageDecodingContext(request: Test.request, data: data, isCompleted: false, previewPolicy: .default(for: data))
        #expect(context.previewPolicy == .incremental)
        let decoder = try #require(ImageDecoders.Default(context: context))

        let preview = try #require(decoder.decodePartiallyDownloadedData(data.prefix(data.count * 3 / 4)))
        let final = try decoder.decode(data)

        #expect(final.image.size == CGSize(width: 300, height: 400))
        #expect(preview.image.size == final.image.size)
#if canImport(UIKit)
        // Carried by the image, as `UIImage(data:)` does, not baked into the pixels
        #expect(preview.image.imageOrientation == .right)
        #expect(preview.image.sizeInPixels == CGSize(width: 400, height: 300))
#endif
    }

    @Test func thumbnailPolicyPreviewIsDisplayedWithTheOrientationOfTheFinalImage() throws {
        let data = makeRotatedJPEG(isProgressive: false)
        let context = ImageDecodingContext(request: Test.request, data: data, isCompleted: false, previewPolicy: .thumbnail)
        let decoder = try #require(ImageDecoders.Default(context: context))

        let preview = try #require(decoder.decodePartiallyDownloadedData(data.prefix(data.count * 3 / 4)))
        let final = try decoder.decode(data)

        #expect(final.image.size == CGSize(width: 300, height: 400))
        #expect(preview.image.size == final.image.size)
    }

    /// A 400×300 JPEG declaring orientation 6 (`.right`), displayed as
    /// 300×400, with an embedded thumbnail for the `.thumbnail` policy.
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

    // MARK: GIF

    @Test func gifPreviewIsNumberedLikeAnyOther() throws {
        // Documented on the decoder: the previews are numbered in the order
        // they are produced, and the final image counts the ones before it.
        let data = Test.data(name: "cat", extension: "gif")
        let decoder = ImageDecoders.Default()

        let preview = try #require(decoder.decodePartiallyDownloadedData(data[...60000]))
        let final = try decoder.decode(data)

        #expect(preview.userInfo[.scanNumberKey] as? Int == 1)
        #expect(final.userInfo[.scanNumberKey] as? Int == 1)
        #expect(decoder.numberOfScans == 1)
    }

    @Test func gifPreviewIsRetriedUntilThereIsEnoughDataToDecode() throws {
        // The flag that limits a GIF to a single preview must only be set by a
        // preview that was actually produced.
        let data = Test.data(name: "cat", extension: "gif")
        let decoder = ImageDecoders.Default()

        #expect(decoder.decodePartiallyDownloadedData(data[0..<10]) == nil)

        let preview = try #require(decoder.decodePartiallyDownloadedData(data[...60000]))
        #expect(preview.isPreview)
        #expect(preview.type == .gif)
        #expect(preview.image.sizeInPixels == CGSize(width: 500, height: 279))
        #expect(decoder.decodePartiallyDownloadedData(data[...120000]) == nil)
    }

    @Test func onlyTheFinalGIFCarriesTheAnimation() throws {
        // A preview is a still of the frames downloaded so far; the data and
        // the parsed animation only travel with the final image.
        let data = Test.data(name: "cat", extension: "gif")
        let decoder = ImageDecoders.Default()

        let preview = try #require(decoder.decodePartiallyDownloadedData(data[...60000]))
        let final = try decoder.decode(data)

        #expect(preview.data == nil)
        #expect(preview.animation == nil)
        #expect(final.data == data)
        let animation = try #require(final.animation)
        #expect(animation.frameCount == AnimatedImageSource(data: data)?.frameCount)
    }

    // MARK: Invalid Data

    @Test(arguments: [ImagePipeline.PreviewPolicy.incremental, .thumbnail, .disabled])
    func garbageProducesNoPreviewUnderAnyPolicy(policy: ImagePipeline.PreviewPolicy) {
        let data = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let context = ImageDecodingContext(request: Test.request, data: data, isCompleted: false, previewPolicy: policy)
        guard let decoder = ImageDecoders.Default(context: context) else {
            Issue.record("The default decoder is always created")
            return
        }

        for count in [1, 16, 1024, 4096] {
            #expect(decoder.decodePartiallyDownloadedData(data.prefix(count)) == nil)
        }
        #expect(decoder.numberOfScans == 0)
        #expect(throws: ImageDecodingError.self) {
            try decoder.decode(data)
        }
    }

    // MARK: Scale

#if canImport(UIKit)
    @Test func previewsHaveTheScaleOfTheRequest() throws {
        // Every path that produces a preview – incremental, the thumbnail
        // fallback, the thumbnail policy, and the GIF one – builds the image
        // itself, so each one has to carry the scale over.
        var request = Test.request
        request.scale = 3
        func makeDecoder(_ policy: ImagePipeline.PreviewPolicy) throws -> ImageDecoders.Default {
            try #require(ImageDecoders.Default(context: ImageDecodingContext(request: request, data: Data(), isCompleted: false, previewPolicy: policy)))
        }
        let progressive = Test.data(name: "progressive", extension: "jpeg")
        let tricky = Test.data(name: "tricky_progressive", extension: "jpeg")
        let gif = Test.data(name: "cat", extension: "gif")

        let incremental = try #require(try makeDecoder(.incremental).decodePartiallyDownloadedData(progressive[0..<5000]))
        let fallback = try #require(try makeDecoder(.incremental).decodePartiallyDownloadedData(tricky[0..<6000]))
        let thumbnail = try #require(try makeDecoder(.thumbnail).decodePartiallyDownloadedData(progressive[0..<2000]))
        let gifPreview = try #require(try makeDecoder(.incremental).decodePartiallyDownloadedData(gif[...60000]))
        let final = try makeDecoder(.incremental).decode(progressive)

        for container in [incremental, fallback, thumbnail, gifPreview, final] {
            #expect(container.image.scale == 3)
        }
        #expect(final.image.size == CGSize(width: 150, height: 100))
    }
#endif
}

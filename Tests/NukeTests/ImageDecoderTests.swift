// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import ImageIO
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImageDecoderTests {
    @Test func decodePNG() throws {
        // Given
        let data = Test.data(name: "fixture", extension: "png")
        let decoder = ImageDecoders.Default()

        // When
        let container = try decoder.decode(data)

        // Then
        #expect(container.type == .png)
        #expect(!container.isPreview)
        #expect(container.data == nil)
        #expect(container.userInfo.isEmpty)
    }

    @Test func decodeJPEG() throws {
        // Given
        let data = Test.data(name: "baseline", extension: "jpeg")
        let decoder = ImageDecoders.Default()

        // When
        let container = try decoder.decode(data)

        // Then
        #expect(container.type == .jpeg)
        #expect(!container.isPreview)
        #expect(container.data == nil)
        #expect(container.userInfo.isEmpty)
    }

    @Test func decodingProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        let decoder = ImageDecoders.Default()

        // Not enough data for progressive detection (SOF2 not yet reached)
        #expect(decoder.decodePartiallyDownloadedData(data[0...358]) == nil)
        #expect(decoder.numberOfScans == 0)

        // After SOF2 marker, CGImageSource produces previews immediately
        let scan1 = decoder.decodePartiallyDownloadedData(data[0...500])
        #expect(scan1 != nil)
        #expect(scan1?.isPreview == true)
        #expect(decoder.numberOfScans == 1)
        if let image = scan1?.image {
#if os(macOS)
            #expect(image.size.width == 450)
            #expect(image.size.height == 300)
#else
            #expect(image.size.width * image.scale == 450)
            #expect(image.size.height * image.scale == 300)
#endif
        }
        #expect(scan1?.userInfo[.scanNumberKey] as? Int == 1)

        // More data produces additional previews
        let scan2 = decoder.decodePartiallyDownloadedData(data[0...5000])
        #expect(scan2 != nil)
        #expect(scan2?.isPreview == true)
        #expect(decoder.numberOfScans == 2)

        // Feed all data
        let final = decoder.decodePartiallyDownloadedData(data)
        #expect(final != nil)
        #expect(decoder.numberOfScans == 3)
    }

    @Test func previewPolicyPassedToDecoder() throws {
        let data = Test.data(name: "progressive", extension: "jpeg")

        // The policy defaults to .incremental
        #expect(ImageDecodingContext(request: Test.request, data: data).previewPolicy == .incremental)

        // The policy given to the initializer reaches the decoder
        let context = ImageDecodingContext(request: Test.request, data: data, isCompleted: false, previewPolicy: .thumbnail)
        let decoder = try #require(ImageDecoders.Default(context: context))
        #expect(decoder.previewPolicy == .thumbnail)
    }

    @Test func decodingBaselineJPEG() throws {
        let data = Test.data(name: "baseline", extension: "jpeg")

        // Default policy for baseline JPEG is .disabled — no previews
        let context = ImageDecodingContext.mock(data: data, previewPolicy: .default(for: data))
        let decoder = try #require(ImageDecoders.Default(context: context))

        let partial = decoder.decodePartiallyDownloadedData(data[0...(data.count / 2)])
        #expect(partial == nil)

        // Full decode always works
        let container = try decoder.decode(data)
        #expect(container.type == .jpeg)
        #expect(!container.isPreview)
    }

    @Test func decodingBaselineJPEGWithIncrementalPolicy() throws {
        let data = Test.data(name: "baseline", extension: "jpeg")

        // With .incremental policy, Image I/O produces partial top-down renders
        let context = ImageDecodingContext.mock(data: data, previewPolicy: .incremental)
        let decoder = try #require(ImageDecoders.Default(context: context))

        let partial = decoder.decodePartiallyDownloadedData(data[0...(data.count / 2)])
        #expect(partial != nil)
        #expect(partial?.isPreview == true)

        let container = try decoder.decode(data)
        #expect(container.type == .jpeg)
        #expect(!container.isPreview)
    }

    @Test func decodingBaselineJPEGWithThumbnailPolicy() throws {
        let data = Test.data(name: "baseline", extension: "jpeg")

        let context = ImageDecodingContext.mock(data: data, previewPolicy: .thumbnail)
        let decoder = try #require(ImageDecoders.Default(context: context))

        // Baseline JPEG typically has no embedded EXIF thumbnail
        _ = decoder.decodePartiallyDownloadedData(data)
        // Whether this returns an image depends on the specific file;
        // either way, subsequent calls should return nil
        #expect(decoder.decodePartiallyDownloadedData(data) == nil)
    }

    @Test func decodingProgressiveJPEGWithDisabledPolicy() throws {
        let data = Test.data(name: "progressive", extension: "jpeg")

        let context = ImageDecodingContext.mock(data: data, previewPolicy: .disabled)
        let decoder = try #require(ImageDecoders.Default(context: context))

        // No previews with .disabled policy
        #expect(decoder.decodePartiallyDownloadedData(data[0...500]) == nil)
        #expect(decoder.decodePartiallyDownloadedData(data[0...5000]) == nil)
        #expect(decoder.numberOfScans == 0)

        // Full decode still works
        let container = try decoder.decode(data)
        #expect(container.type == .jpeg)
    }

    @Test func decodingPNGPartialData() throws {
        let data = Test.data(name: "fixture", extension: "png")

        // Default policy for PNG is .disabled — no previews
        let context = ImageDecodingContext.mock(data: data, previewPolicy: .default(for: data))
        let decoder = try #require(ImageDecoders.Default(context: context))

        #expect(decoder.decodePartiallyDownloadedData(data[0...100]) == nil)

        // Full decode still works
        let container = try decoder.decode(data)
        #expect(container.type == .png)
        #expect(!container.isPreview)
    }

    @Test func decoderAlwaysCreatedFromContext() throws {
        // The decoder should always initialize, regardless of image format.
        let jpegData = Test.data(name: "baseline", extension: "jpeg")
        let jpegContext = ImageDecodingContext.mock(data: jpegData)
        #expect(ImageDecoders.Default(context: jpegContext) != nil)

        let pngData = Test.data(name: "fixture", extension: "png")
        let pngContext = ImageDecodingContext.mock(data: pngData)
        #expect(ImageDecoders.Default(context: pngContext) != nil)

        let progressiveData = Test.data(name: "progressive", extension: "jpeg")
        let progressiveContext = ImageDecodingContext.mock(data: progressiveData)
        #expect(ImageDecoders.Default(context: progressiveContext) != nil)
    }

    @Test func defaultPreviewPolicy() {
        // Progressive JPEG → .incremental
        let progressiveData = Test.data(name: "progressive", extension: "jpeg")
        #expect(ImagePipeline.PreviewPolicy.default(for: progressiveData) == .incremental)

        // Baseline JPEG → .disabled
        let baselineData = Test.data(name: "baseline", extension: "jpeg")
        #expect(ImagePipeline.PreviewPolicy.default(for: baselineData) == .disabled)

        // PNG → .disabled
        let pngData = Test.data(name: "fixture", extension: "png")
        #expect(ImagePipeline.PreviewPolicy.default(for: pngData) == .disabled)

        // GIF → .incremental
        let gifData = Test.data(name: "cat", extension: "gif")
        #expect(ImagePipeline.PreviewPolicy.default(for: gifData) == .incremental)
    }

    @Test func decodingTrickyProgressiveJPEG() throws {
        let data = Test.data(name: "tricky_progressive", extension: "jpeg")
        let decoder = ImageDecoders.Default()

        // This progressive JPEG has a ~7 KB EXIF header (SOF2 at offset 7394).
        // CGImageSourceCreateIncremental fails to produce images until enough
        // data past SOF2 is available. With small chunks, the thumbnail
        // fallback kicks in first.
        #expect(decoder.decodePartiallyDownloadedData(data[0...2000]) == nil)

        // With enough data, the decoder produces a preview (either via
        // thumbnail fallback or incremental decoding).
        let preview = decoder.decodePartiallyDownloadedData(data[0...8000])
        #expect(preview != nil)
        #expect(preview?.isPreview == true)
        #expect(decoder.numberOfScans == 1)

        // Full decode at full resolution
        let container = try decoder.decode(data)
        #expect(container.image.sizeInPixels == CGSize(width: 450, height: 300))
    }

    @Test func decodeGIF() throws {
        // Given
        let data = Test.data(name: "cat", extension: "gif")
        let decoder = ImageDecoders.Default()

        // When
        let container = try decoder.decode(data)

        // Then
        #expect(container.type == .gif)
        #expect(!container.isPreview)
        #expect(container.data != nil)
        #expect(container.userInfo.isEmpty)
    }

    @Test func decodeHEIC() throws {
        // Given
        let data = Test.data(name: "img_751", extension: "heic")
        let decoder = ImageDecoders.Default()

        // When
        let container = try decoder.decode(data)

        // Then
        #expect(container.type == AssetType.heic)
        #expect(!container.isPreview)
        #expect(container.data == nil)
        #expect(container.userInfo.isEmpty)
    }

    @Test func decodeICO() throws {
        // Given
        let data = Test.data(name: "fixture", extension: "ico")
        let decoder = ImageDecoders.Default()

        // When
        let container = try decoder.decode(data)

        // Then
        #expect(container.type == AssetType.ico)
        #expect(!container.isPreview)
        #expect(container.data == nil)
        #expect(container.userInfo.isEmpty)
        #expect(container.image.sizeInPixels == CGSize(width: 32, height: 32))
    }

    @Test func decodingGIFDataAttached() throws {
        let data = Test.data(name: "cat", extension: "gif")
        #expect(try ImageDecoders.Default().decode(data).data != nil)
    }

    // MARK: - Animations

    @Test func decodingAnAnimationAttachesItsMetadata() throws {
        let data = Test.animatedGIF(frameCount: 5, delays: Array(repeating: 0.05, count: 5))

        let container = try ImageDecoders.Default().decode(data)

        // Parsed here, on the decoding queue, so that the views displaying the
        // image don't each parse it again on the main thread.
        let animation = try #require(container.animation)
        #expect(animation.frameCount == 5)
        #expect(animation.duration == 0.25)
        // The same buffer, shared rather than copied, which is what keeps the
        // animation from doubling what the container costs the memory cache.
        #expect(animation.data == container.data)
    }

    @Test func decodingASingleFrameGIFAttachesNoAnimation() throws {
        let data = Test.animatedGIF(frameCount: 1)

        let container = try ImageDecoders.Default().decode(data)

        // The data is attached on a header sniff, which can't tell a GIF that
        // animates from one that doesn't. The parse can, and that is the
        // difference between the two properties.
        #expect(container.data != nil)
        #expect(container.animation == nil)
    }

    @Test func decodingAThumbnailAttachesNoAnimation() throws {
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 8)
        let context = ImageDecodingContext(request: request, data: Test.animatedGIF(size: CGSize(width: 64, height: 64)))
        let decoder = try #require(ImageDecoders.Default(context: context))

        let container = try decoder.decode(context.data)

        // The image is deliberately smaller than the animation the data holds,
        // and playing it would undo the downscaling the request asked for.
        #expect(container.data == nil)
        #expect(container.animation == nil)
    }

    @Test func animationParsingCanBeTurnedOff() throws {
        let data = Test.animatedGIF(frameCount: 5)
        let context = ImageDecodingContext(request: Test.request, data: data, isAnimatedImageParsingEnabled: false)
        let decoder = try #require(ImageDecoders.Default(context: context))

        let container = try decoder.decode(data)

        // The data still travels, so a renderer that parses it itself is
        // unaffected; what is skipped is the walk of the frame metadata.
        #expect(container.data != nil)
        #expect(container.animation == nil)
    }

    @Test func decodingGIFPreview() throws {
        let data = Test.data(name: "cat", extension: "gif")
        #expect(data.count == 427672) // 427 KB
        let chunk = data[...60000] // 6 KB
        let response = try ImageDecoders.Default().decode(chunk)
        #expect(response.image.sizeInPixels == CGSize(width: 500, height: 279))
    }

    @Test func decodingGIFPreviewGeneratedOnlyOnce() throws {
        let data = Test.data(name: "cat", extension: "gif")
        #expect(data.count == 427672) // 427 KB
        let chunk = data[...60000] // 6 KB

        let context = ImageDecodingContext.mock(data: chunk)
        let decoder = try #require(ImageDecoders.Default(context: context))

        #expect(decoder.decodePartiallyDownloadedData(chunk) != nil)
        #expect(decoder.decodePartiallyDownloadedData(chunk) == nil)
    }

    @Test func decodingGIFPreviewWithDisabledPolicy() throws {
        let data = Test.data(name: "cat", extension: "gif")
        let chunk = data[...60000]

        let context = ImageDecodingContext.mock(data: chunk, previewPolicy: .disabled)
        let decoder = try #require(ImageDecoders.Default(context: context))

        // No previews with the .disabled policy, GIFs included
        #expect(decoder.decodePartiallyDownloadedData(chunk) == nil)
        #expect(decoder.decodePartiallyDownloadedData(data[...120000]) == nil)
        #expect(decoder.numberOfScans == 0)

        // Full decode still works
        let container = try decoder.decode(data)
        #expect(container.type == .gif)
        #expect(!container.isPreview)
    }

    @Test func decodingGIFPreviewWithThumbnailPolicy() throws {
        let data = Test.data(name: "cat", extension: "gif")
        let chunk = data[...60000]

        let context = ImageDecodingContext.mock(data: chunk, previewPolicy: .thumbnail)
        let decoder = try #require(ImageDecoders.Default(context: context))

        // GIFs can't be decoded incrementally, so a single preview is still
        // generated for any policy other than .disabled
        #expect(decoder.decodePartiallyDownloadedData(chunk) != nil)
        #expect(decoder.decodePartiallyDownloadedData(chunk) == nil)
    }

    @Test func decodingPNGDataNotAttached() throws {
        let data = Test.data(name: "fixture", extension: "png")
        let container = try ImageDecoders.Default().decode(data)
        #expect(container.data == nil)
    }

#if os(iOS) || os(macOS) || os(visionOS)
    @Test func decodeBaselineWebP() throws {
        let data = Test.data(name: "baseline", extension: "webp")
        let container = try ImageDecoders.Default().decode(data)
        #expect(container.image.sizeInPixels == CGSize(width: 550, height: 368))
        #expect(container.data == nil)
    }
#endif

    // MARK: - Invalid / Corrupted Data

    @Test func decodeRandomDataThrows() {
        // GIVEN - bytes that share no resemblance with any image format
        let data = Data(repeating: 0xAB, count: 512)
        let decoder = ImageDecoders.Default()

        // WHEN / THEN - decoding must throw (not crash)
        #expect(throws: (any Error).self) {
            try decoder.decode(data)
        }
    }

    @Test func decodeEmptyDataThrows() {
        let decoder = ImageDecoders.Default()
        #expect(throws: (any Error).self) {
            try decoder.decode(Data())
        }
    }

    @Test func partialDataReturnsNilForUnsupportedFormat() {
        // GIVEN - only 2 bytes of PNG data (not enough to decode)
        let data = Test.data(name: "fixture", extension: "png")
        let decoder = ImageDecoders.Default()

        // WHEN - attempt partial decode with too-little data
        let preview = decoder.decodePartiallyDownloadedData(data[0..<2])

        // THEN - no preview produced for this tiny slice
        #expect(preview == nil)
    }

    // MARK: Animated Images

    @Test func attachesDataToAnimatedPNG() throws {
        // GIVEN an APNG, which decodes to its first frame and needs its data to
        // be playable
        let data = try #require(Test.animatedPNG())
        let decoder = ImageDecoders.Default()

        let container = try decoder.decode(data)

        #expect(container.type == .png)
        #expect(container.data == data)
    }

    @Test func attachesDataToAnimatedHEIC() throws {
        // The end of the path the two HEIC bugs lived on: the file leads with
        // the `msf1` brand, which used to sniff as no type at all, and a type
        // the pipeline can't name is an animation it never attaches the data to.
        guard let data = Test.animatedHEICS() else {
            return // Image I/O on this platform can't write a HEIC sequence
        }
        let decoder = ImageDecoders.Default()

        let container = try decoder.decode(data)

        #expect(container.type == .heic)
        #expect(container.data == data)
    }

    @Test func attachesDataToAnimatedWebP() throws {
        let data = Test.data(name: "animated", extension: "webp")
        let decoder = ImageDecoders.Default()

        let container = try decoder.decode(data)

        #expect(container.type == .webp)
        #expect(container.data == data)
    }

    @Test func attachesDataToAnimatedAVIF() throws {
        let data = Test.data(name: "animated", extension: "avif")
        let decoder = ImageDecoders.Default()

        let container = try decoder.decode(data)

        #expect(container.type == .avif)
        #expect(container.data == data)
        #expect(container.animation?.frameCount == 3)
    }

    @Test func doesNotAttachDataToStaticWebP() throws {
        let decoder = ImageDecoders.Default()

        let container = try decoder.decode(Test.data(name: "baseline", extension: "webp"))

        #expect(container.type == .webp)
        #expect(container.data == nil)
    }

    @Test func doesNotAttachDataToStaticPNG() throws {
        let decoder = ImageDecoders.Default()

        let container = try decoder.decode(Test.staticPNG())

        #expect(container.data == nil)
    }

    @Test func doesNotAttachDataToAThumbnail() throws {
        // The data is the full-size animation; playing it would undo the
        // downscaling the request asked for.
        let data = Test.data(name: "cat", extension: "gif")
        let request = ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 32) }
        let context = ImageDecodingContext(request: request, data: data)
        let decoder = try #require(ImageDecoders.Default(context: context))

        let container = try decoder.decode(data)

        #expect(container.type == .gif)
        #expect(container.data == nil)
    }
}

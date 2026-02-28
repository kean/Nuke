// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import ImageIO
@testable import Nuke

@Suite struct ImageDecoderTests {
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


    @Test func decodingBaselineJPEG() throws {
        let data = Test.data(name: "baseline", extension: "jpeg")

        // Default policy for baseline JPEG is .disabled — no previews
        var context = ImageDecodingContext.mock(data: data)
        context.previewPolicy = .default(for: data)
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
        var context = ImageDecodingContext.mock(data: data)
        context.previewPolicy = .incremental
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

        var context = ImageDecodingContext.mock(data: data)
        context.previewPolicy = .thumbnail
        let decoder = try #require(ImageDecoders.Default(context: context))

        // Baseline JPEG typically has no embedded EXIF thumbnail
        _ = decoder.decodePartiallyDownloadedData(data)
        // Whether this returns an image depends on the specific file;
        // either way, subsequent calls should return nil
        #expect(decoder.decodePartiallyDownloadedData(data) == nil)
    }

    @Test func decodingProgressiveJPEGWithDisabledPolicy() throws {
        let data = Test.data(name: "progressive", extension: "jpeg")

        var context = ImageDecodingContext.mock(data: data)
        context.previewPolicy = .disabled
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
        var context = ImageDecodingContext.mock(data: data)
        context.previewPolicy = .default(for: data)
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

    @Test func decodingGIFDataAttached() throws {
        let data = Test.data(name: "cat", extension: "gif")
        #expect(try ImageDecoders.Default().decode(data).data != nil)
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
}

@Suite struct ImageTypeTests {
    // MARK: PNG

    @Test func detectPNG() {
        let data = Test.data(name: "fixture", extension: "png")
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<7]) == nil)
        #expect(AssetType(data[0..<8]) == .png)
        #expect(AssetType(data) == .png)
    }

    // MARK: GIF

    @Test func detectGIF() {
        let data = Test.data(name: "cat", extension: "gif")
        #expect(AssetType(data) == .gif)
    }

    // MARK: JPEG

    @Test func detectBaselineJPEG() {
        let data = Test.data(name: "baseline", extension: "jpeg")
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<2]) == nil)
        #expect(AssetType(data[0..<3]) == .jpeg)
        #expect(AssetType(data) == .jpeg)
    }

    @Test func detectProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        // Not enough data
        #expect(AssetType(Data()) == nil)
        #expect(AssetType(data[0..<2]) == nil)

        // Enough to determine image format
        #expect(AssetType(data[0..<3]) == .jpeg)
        #expect(AssetType(data[0..<33]) == .jpeg)

        // Full image
        #expect(AssetType(data) == .jpeg)
    }

    // MARK: WebP

    @Test func detectBaselineWebP() {
        let data = Test.data(name: "baseline", extension: "webp")
        #expect(AssetType(data[0..<1]) == nil)
        #expect(AssetType(data[0..<2]) == nil)
        #expect(AssetType(data[0..<12]) == .webp)
        #expect(AssetType(data) == .webp)
    }
}

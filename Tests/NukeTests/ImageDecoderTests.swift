// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
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
        let decoder = ImageDecoders.Default()

        // Image I/O produces partial top-down renders for baseline JPEGs
        let partial = decoder.decodePartiallyDownloadedData(data[0...(data.count / 2)])
        #expect(partial != nil)
        #expect(partial?.isPreview == true)

        // Full decode always works after feeding partial data
        let container = try decoder.decode(data)
        #expect(container.type == .jpeg)
        #expect(!container.isPreview)
    }

    @Test func decodingPNGPartialData() throws {
        let data = Test.data(name: "fixture", extension: "png")
        let decoder = ImageDecoders.Default()

        // Standard PNG is not a progressive format — Image I/O typically
        // does not produce intermediate images for partial data
        #expect(decoder.decodePartiallyDownloadedData(data[0...100]) == nil)

        // Full decode still works after feeding partial data
        let container = try decoder.decode(data)
        #expect(container.type == .png)
        #expect(!container.isPreview)
    }

    @Test func decoderAlwaysCreatedFromContext() throws {
        // The decoder should always initialize, regardless of image format.
        // Image I/O decides what to do with partial data.
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

    @Test func decodingTrickyProgressiveJPEG() throws {
        let data = Test.data(name: "tricky_progressive", extension: "jpeg")
        let decoder = ImageDecoders.Default()

        // CGImageSourceCreateIncremental does not produce intermediate images
        // for this JPEG with large EXIF data, so no progressive previews are
        // generated. Verify that it still decodes correctly as a full image.
        #expect(decoder.decodePartiallyDownloadedData(data[0...886]) == nil)
        #expect(decoder.decodePartiallyDownloadedData(data) == nil)
        #expect(decoder.numberOfScans == 0)

        // Full decode still works
        let container = try decoder.decode(data)
        #expect(container.image.sizeInPixels == CGSize(width: 352, height: 198))
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

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
    @Test func decodeBaselineWebP() throws {
        if #available(OSX 11.0, iOS 14.0, watchOS 7.0, tvOS 999.0, *) {
            let data = Test.data(name: "baseline", extension: "webp")
            let container = try ImageDecoders.Default().decode(data)
            #expect(container.image.sizeInPixels == CGSize(width: 550, height: 368))
            #expect(container.data == nil)
        }
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

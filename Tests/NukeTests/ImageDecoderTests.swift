// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke

@Suite struct ImageDecoderTests {
    @Test func decodePNG() throws {
        // Given
        let data = Test.data(name: "fixture", extension: "png")
        let decoder = ImageDecoders.Default()

        // When
        let container = try #require(try decoder.decode(data))

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
        let container = try #require(try decoder.decode(data))

        // Then
        #expect(container.type == .jpeg)
        #expect(!container.isPreview)
        #expect(container.data == nil)
        #expect(container.userInfo.isEmpty)
    }

    @Test func decodingProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        let decoder = ImageDecoders.Default()

        // Just before the Start Of Frame
        #expect(decoder.decodePartiallyDownloadedData(data[0...358]) == nil)
        #expect(decoder.numberOfScans == 0)

        // Right after the Start Of Frame
        #expect(decoder.decodePartiallyDownloadedData(data[0...359]) == nil)
        #expect(decoder.numberOfScans == 0) // still haven't finished the first scan // still haven't finished the first scan

        // Just before the first Start Of Scan
        #expect(decoder.decodePartiallyDownloadedData(data[0...438]) == nil)
        #expect(decoder.numberOfScans == 0) // still haven't finished the first scan // still haven't finished the first scan

        // Found the first Start Of Scan
        #expect(decoder.decodePartiallyDownloadedData(data[0...439]) == nil)
        #expect(decoder.numberOfScans == 1)

        // Found the second Start of Scan
        let scan1 = decoder.decodePartiallyDownloadedData(data[0...2952])
        #expect(scan1 != nil)
        #expect(scan1?.isPreview == true)
        if let image = scan1?.image {
#if os(macOS)
            #expect(image.size.width == 450)
            #expect(image.size.height == 300)
#else
            #expect(image.size.width * image.scale == 450)
            #expect(image.size.height * image.scale == 300)
#endif
        }
        #expect(decoder.numberOfScans == 2)
        #expect(scan1?.userInfo[.scanNumberKey] as? Int == 2)

        // Feed all data and see how many scans are there
        // In practice the moment we finish receiving data we call
        // `decode(data: data, isCompleted: true)` so we might not scan all the
        // of the bytes and encounter all of the scans (e.g. the final chunk
        // of data that we receive contains multiple scans).
        #expect(decoder.decodePartiallyDownloadedData(data) != nil)
        #expect(decoder.numberOfScans == 10)
    }

    @Test func decodeGIF() throws {
        // Given
        let data = Test.data(name: "cat", extension: "gif")
        let decoder = ImageDecoders.Default()

        // When
        let container = try #require(try decoder.decode(data))

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
        let container = try #require(try decoder.decode(data))

        // Then
        #expect(container.type == .heic)
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
        #expect(data.count == 427672) // 427 KB // 427 KB
        let chunk = data[...60000] // 6 KB
        let response = try ImageDecoders.Default().decode(chunk)
        #expect(response.image.sizeInPixels == CGSize(width: 500, height: 279))
    }

    @Test func decodingGIFPreviewGeneratedOnlyOnce() throws {
        let data = Test.data(name: "cat", extension: "gif")
        #expect(data.count == 427672) // 427 KB // 427 KB
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

@Suite struct ImagePropertiesTests {
    // MARK: JPEG

    @Test func detectBaselineJPEG() {
        let data = Test.data(name: "baseline", extension: "jpeg")
        #expect(ImageProperties.JPEG(data[0..<1]) == nil)
        #expect(ImageProperties.JPEG(data[0..<2]) == nil)
        #expect(ImageProperties.JPEG(data[0..<3]) == nil)
        #expect(ImageProperties.JPEG(data)?.isProgressive == false)
    }

    @Test func detectProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        // Not enough data
        #expect(ImageProperties.JPEG(Data()) == nil)
        #expect(ImageProperties.JPEG(data[0..<2]) == nil)

        // Enough to determine image format
        #expect(ImageProperties.JPEG(data[0..<3]) == nil)
        #expect(ImageProperties.JPEG(data[0...30]) == nil)

        // Just before the first scan
        #expect(ImageProperties.JPEG(data[0...358]) == nil)
        #expect(ImageProperties.JPEG(data[0...359])?.isProgressive == true)

        // Full image
        #expect(ImageProperties.JPEG(data[0...359])?.isProgressive == true)
    }
}

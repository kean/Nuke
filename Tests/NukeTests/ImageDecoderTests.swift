// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageDecoderTests: XCTestCase {
    func testDecodePNG() throws {
        // Given
        let data = Test.data(name: "fixture", extension: "png")
        let decoder = ImageDecoders.Default()
        
        // When
        let container = try XCTUnwrap(decoder.decode(data))
        
        // Then
        XCTAssertEqual(container.type, .png)
        XCTAssertFalse(container.isPreview)
        XCTAssertNil(container.data)
        XCTAssertTrue(container.userInfo.isEmpty)
    }
    
    func testDecodeJPEG() throws {
        // Given
        let data = Test.data(name: "baseline", extension: "jpeg")
        let decoder = ImageDecoders.Default()
        
        // When
        let container = try XCTUnwrap(decoder.decode(data))
        
        // Then
        XCTAssertEqual(container.type, .jpeg)
        XCTAssertFalse(container.isPreview)
        XCTAssertNil(container.data)
        XCTAssertTrue(container.userInfo.isEmpty)
    }
    
    func testDecodingProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        let decoder = ImageDecoders.Default()
        
        // Just before the Start Of Frame
        XCTAssertNil(decoder.decodePartiallyDownloadedData(data[0...358]))
        XCTAssertEqual(decoder.numberOfScans, 0)
        
        // Right after the Start Of Frame
        XCTAssertNil(decoder.decodePartiallyDownloadedData(data[0...359]))
        XCTAssertEqual(decoder.numberOfScans, 0) // still haven't finished the first scan
        
        // Just before the first Start Of Scan
        XCTAssertNil(decoder.decodePartiallyDownloadedData(data[0...438]))
        XCTAssertEqual(decoder.numberOfScans, 0) // still haven't finished the first scan
        
        // Found the first Start Of Scan
        XCTAssertNil(decoder.decodePartiallyDownloadedData(data[0...439]))
        XCTAssertEqual(decoder.numberOfScans, 1)
        
        // Found the second Start of Scan
        let scan1 = decoder.decodePartiallyDownloadedData(data[0...2952])
        XCTAssertNotNil(scan1)
        XCTAssertEqual(scan1?.isPreview, true)
        if let image = scan1?.image {
#if os(macOS)
            XCTAssertEqual(image.size.width, 450)
            XCTAssertEqual(image.size.height, 300)
#else
            XCTAssertEqual(image.size.width * image.scale, 450)
            XCTAssertEqual(image.size.height * image.scale, 300)
#endif
        }
        XCTAssertEqual(decoder.numberOfScans, 2)
        XCTAssertEqual(scan1?.userInfo[.scanNumberKey] as? Int, 2)
        
        // Feed all data and see how many scans are there
        // In practice the moment we finish receiving data we call
        // `decode(data: data, isCompleted: true)` so we might not scan all the
        // of the bytes and encounter all of the scans (e.g. the final chunk
        // of data that we receive contains multiple scans).
        XCTAssertNotNil(decoder.decodePartiallyDownloadedData(data))
        XCTAssertEqual(decoder.numberOfScans, 10)
    }
    
    func testDecodeGIF() throws {
        // Given
        let data = Test.data(name: "cat", extension: "gif")
        let decoder = ImageDecoders.Default()
        
        // When
        let container = try XCTUnwrap(decoder.decode(data))
        
        // Then
        XCTAssertEqual(container.type, .gif)
        XCTAssertFalse(container.isPreview)
        XCTAssertNotNil(container.data)
        XCTAssertTrue(container.userInfo.isEmpty)
    }
    
    func testDecodeHEIC() throws {
        // Given
        let data = Test.data(name: "img_751", extension: "heic")
        let decoder = ImageDecoders.Default()
        
        // When
        let container = try XCTUnwrap(decoder.decode(data))
        
        // Then
        XCTAssertNil(container.type) // TODO: update when HEIF support is added
        XCTAssertFalse(container.isPreview)
        XCTAssertNil(container.data)
        XCTAssertTrue(container.userInfo.isEmpty)
    }
    
    func testDecodingGIFDataAttached() throws {
        let data = Test.data(name: "cat", extension: "gif")
        XCTAssertNotNil(try ImageDecoders.Default().decode(data).data)
    }
    
    func testDecodingGIFPreview() throws {
        let data = Test.data(name: "cat", extension: "gif")
        XCTAssertEqual(data.count, 427672) // 427 KB
        let chunk = data[...60000] // 6 KB
        let response = try ImageDecoders.Default().decode(chunk)
        XCTAssertEqual(response.image.sizeInPixels, CGSize(width: 500, height: 279))
    }
    
    func testDecodingGIFPreviewGeneratedOnlyOnce() throws {
        let data = Test.data(name: "cat", extension: "gif")
        XCTAssertEqual(data.count, 427672) // 427 KB
        let chunk = data[...60000] // 6 KB
        
        let context = ImageDecodingContext.mock(data: chunk)
        let decoder = try XCTUnwrap(ImageDecoders.Default(context: context))
        
        XCTAssertNotNil(decoder.decodePartiallyDownloadedData(chunk))
        XCTAssertNil(decoder.decodePartiallyDownloadedData(chunk))
    }
    
    func testDecodingPNGDataNotAttached() throws {
        let data = Test.data(name: "fixture", extension: "png")
        let container = try ImageDecoders.Default().decode(data)
        XCTAssertNil(container.data)
    }
    
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
    func testDecodeBaselineWebP() throws {
        if #available(OSX 11.0, iOS 14.0, watchOS 7.0, tvOS 999.0, *) {
            let data = Test.data(name: "baseline", extension: "webp")
            let container = try ImageDecoders.Default().decode(data)
            XCTAssertEqual(container.image.sizeInPixels, CGSize(width: 550, height: 368))
            XCTAssertNil(container.data)
        }
    }
#endif
}

class ImageTypeTests: XCTestCase {
    // MARK: PNG
    
    func testDetectPNG() {
        let data = Test.data(name: "fixture", extension: "png")
        XCTAssertNil(AssetType(data[0..<1]))
        XCTAssertNil(AssetType(data[0..<7]))
        XCTAssertEqual(AssetType(data[0..<8]), .png)
        XCTAssertEqual(AssetType(data), .png)
    }
    
    // MARK: GIF
    
    func testDetectGIF() {
        let data = Test.data(name: "cat", extension: "gif")
        XCTAssertEqual(AssetType(data), .gif)
    }
    
    // MARK: JPEG
    
    func testDetectBaselineJPEG() {
        let data = Test.data(name: "baseline", extension: "jpeg")
        XCTAssertNil(AssetType(data[0..<1]))
        XCTAssertNil(AssetType(data[0..<2]))
        XCTAssertEqual(AssetType(data[0..<3]), .jpeg)
        XCTAssertEqual(AssetType(data), .jpeg)
    }
    
    func testDetectProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        // Not enough data
        XCTAssertNil(AssetType(Data()))
        XCTAssertNil(AssetType(data[0..<2]))
        
        // Enough to determine image format
        XCTAssertEqual(AssetType(data[0..<3]), .jpeg)
        XCTAssertEqual(AssetType(data[0..<33]), .jpeg)
        
        // Full image
        XCTAssertEqual(AssetType(data), .jpeg)
    }
    
    // MARK: WebP
    
    func testDetectBaselineWebP() {
        let data = Test.data(name: "baseline", extension: "webp")
        XCTAssertNil(AssetType(data[0..<1]))
        XCTAssertNil(AssetType(data[0..<2]))
        XCTAssertEqual(AssetType(data[0..<12]), .webp)
        XCTAssertEqual(AssetType(data), .webp)
    }
}

class ImagePropertiesTests: XCTestCase {
    // MARK: JPEG
    
    func testDetectBaselineJPEG() {
        let data = Test.data(name: "baseline", extension: "jpeg")
        XCTAssertNil(ImageProperties.JPEG(data[0..<1]))
        XCTAssertNil(ImageProperties.JPEG(data[0..<2]))
        XCTAssertNil(ImageProperties.JPEG(data[0..<3]))
        XCTAssertEqual(ImageProperties.JPEG(data)?.isProgressive, false)
    }
    
    func testDetectProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        // Not enough data
        XCTAssertNil(ImageProperties.JPEG(Data()))
        XCTAssertNil(ImageProperties.JPEG(data[0..<2]))
        
        // Enough to determine image format
        XCTAssertNil(ImageProperties.JPEG(data[0..<3]))
        XCTAssertNil(ImageProperties.JPEG(data[0...30]))
        
        // Just before the first scan
        XCTAssertNil(ImageProperties.JPEG(data[0...358]))
        XCTAssertEqual(ImageProperties.JPEG(data[0...359])?.isProgressive, true)
        
        // Full image
        XCTAssertEqual(ImageProperties.JPEG(data[0...359])?.isProgressive, true)
    }
}

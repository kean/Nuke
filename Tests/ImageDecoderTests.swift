// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageDecoderTests: XCTestCase {
    func testDecodingProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        let decoder = ImageDecoders.Default()

        // Just before the Start Of Frame
        XCTAssertNil(decoder.decodePartiallyDownloadedData(data[0...358]))
        XCTAssertNil(decoder.isProgressive)
        XCTAssertEqual(decoder.numberOfScans, 0)

        // Right after the Start Of Frame
        XCTAssertNil(decoder.decodePartiallyDownloadedData(data[0...359]))
        XCTAssertTrue(decoder.isProgressive!)
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
        XCTAssertEqual(scan1?.userInfo[ImageDecoders.Default.scanNumberKey] as? Int, 2)

        // Feed all data and see how many scans are there
        // In practice the moment we finish receiving data we call
        // `decode(data: data, isFinal: true)` so we might not scan all the
        // of the bytes and encounter all of the scans (e.g. the final chunk
        // of data that we receive contains multiple scans).
        XCTAssertNotNil(decoder.decodePartiallyDownloadedData(data))
        XCTAssertEqual(decoder.numberOfScans, 10)
    }

    func testDecodingGIFsDeprecated() {
        XCTAssertFalse(ImagePipeline.Configuration._isAnimatedImageDataEnabled)

        let data = Test.data(name: "cat", extension: "gif")
        XCTAssertNil(ImageDecoders.Default().decode(data)?.image.animatedImageData)

        ImagePipeline.Configuration._isAnimatedImageDataEnabled = true
        XCTAssertNotNil(ImageDecoders.Default().decode(data)?.image.animatedImageData)
        ImagePipeline.Configuration._isAnimatedImageDataEnabled = false
    }

    func testDecodingGIFDataAttached() {
        let data = Test.data(name: "cat", extension: "gif")
        XCTAssertNotNil(ImageDecoders.Default().decode(data)?.data)
    }

    func testDecodingPNGDataNotAttached() {
        let data = Test.data(name: "fixture", extension: "png")
        let container = ImageDecoders.Default().decode(data)
        XCTAssertNotNil(container)
        XCTAssertNil(container?.data)
    }
}

class ImageFormatTests: XCTestCase {
    // MARK: PNG

    func testDetectPNG() {
        let data = Test.data(name: "fixture", extension: "png")
        XCTAssertNil(ImageFormat.format(for: data[0..<1]))
        XCTAssertNil(ImageFormat.format(for: data[0..<7]))
        XCTAssertEqual(ImageFormat.format(for: data[0..<8]), .png)
        XCTAssertEqual(ImageFormat.format(for: data), .png)
    }

    // MARK: GIF

    func testDetectGIF() {
        let data = Test.data(name: "cat", extension: "gif")
        XCTAssertEqual(ImageFormat.format(for: data), .gif)
    }

    // MARK: JPEG

    func testDetectBaselineJPEG() {
        let data = Test.data(name: "baseline", extension: "jpeg")
        XCTAssertNil(ImageFormat.format(for: data[0..<1]))
        XCTAssertNil(ImageFormat.format(for: data[0..<2]))
        XCTAssertEqual(ImageFormat.format(for: data[0..<3]), .jpeg(isProgressive: nil))
        XCTAssertEqual(ImageFormat.format(for: data), .jpeg(isProgressive: false))
    }

    func testDetectProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        // Not enough data
        XCTAssertNil(ImageFormat.format(for: Data()))
        XCTAssertNil(ImageFormat.format(for: data[0..<2]))

        // Enough to determine image format
        XCTAssertEqual(ImageFormat.format(for: data[0..<3]), .jpeg(isProgressive: nil))
        XCTAssertEqual(ImageFormat.format(for: data[0...30]), .jpeg(isProgressive: nil))

        // Just before the first scan
        XCTAssertEqual(ImageFormat.format(for: data[0...358]), .jpeg(isProgressive: nil))
        XCTAssertEqual(ImageFormat.format(for: data[0...359]), .jpeg(isProgressive: true))

        // Full image
        XCTAssertEqual(ImageFormat.format(for: data), .jpeg(isProgressive: true))
    }
}

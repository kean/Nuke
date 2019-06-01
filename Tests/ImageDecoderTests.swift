// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageDecoderTests: XCTestCase {
    func testDecodingProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        let decoder = ImageDecoder()

        // Just before the Start Of Frame
        XCTAssertNil(decoder.decode(data: data[0...358], isFinal: false))
        XCTAssertNil(decoder.isProgressive)
        XCTAssertEqual(decoder.numberOfScans, 0)

        // Right after the Start Of Frame
        XCTAssertNil(decoder.decode(data: data[0...359], isFinal: false))
        XCTAssertTrue(decoder.isProgressive!)
        XCTAssertEqual(decoder.numberOfScans, 0) // still haven't finished the first scan

        // Just before the first Start Of Scan
        XCTAssertNil(decoder.decode(data: data[0...438], isFinal: false))
        XCTAssertEqual(decoder.numberOfScans, 0) // still haven't finished the first scan

        // Found the first Start Of Scan
        XCTAssertNil(decoder.decode(data: data[0...439], isFinal: false))
        XCTAssertEqual(decoder.numberOfScans, 1)

        // Found the second Start of Scan
        let scan1 = decoder.decode(data: data[0...2952], isFinal: false)
        XCTAssertNotNil(scan1)
        if let scan1 = scan1 {
            #if os(macOS)
            XCTAssertEqual(scan1.size.width, 450)
            XCTAssertEqual(scan1.size.height, 300)
            #else
            XCTAssertEqual(scan1.size.width * scan1.scale, 450)
            XCTAssertEqual(scan1.size.height * scan1.scale, 300)
            #endif
        }
        XCTAssertEqual(decoder.numberOfScans, 2)

        // Feed all data and see how many scans are there
        // In practice the moment we finish receiving data we call
        // `decode(data: data, isFinal: true)` so we might not scan all the
        // of the bytes and encounter all of the scans (e.g. the final chunk
        // of data that we receive contains multiple scans).
        XCTAssertNotNil(decoder.decode(data: data, isFinal: false))
        XCTAssertEqual(decoder.numberOfScans, 10)
    }

    func testDecodingGIFs() {
        XCTAssertFalse(ImagePipeline.Configuration.isAnimatedImageDataEnabled)

        let data = Test.data(name: "cat", extension: "gif")
        XCTAssertNil(ImageDecoder().decode(data: data)?.animatedImageData)

        ImagePipeline.Configuration.isAnimatedImageDataEnabled = true
        XCTAssertNotNil(ImageDecoder().decode(data: data)?.animatedImageData)
        ImagePipeline.Configuration.isAnimatedImageDataEnabled = false
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

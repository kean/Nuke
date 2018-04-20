// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

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
        let scan1 = decoder.decode(data: data[0...2592], isFinal: false)
        XCTAssertNotNil(scan1)
        XCTAssertEqual(scan1!.size.width * scan1!.scale, 450)
        XCTAssertEqual(scan1!.size.height * scan1!.scale, 300)
        XCTAssertEqual(decoder.numberOfScans, 2)

        // Feed all data and see how many scans are there
        // In practice the moment we finish receiving data we call
        // `decode(data: data, isFinal: true)` so we might not scan all the
        // of the bytes and encounter all of the scans (e.g. the final chunk
        // of data that we receive contains multiple scans).
        XCTAssertNotNil(decoder.decode(data: data, isFinal: false))
        XCTAssertEqual(decoder.numberOfScans, 11)
    }

    // MARK: Detecting Progressive JPEG

    func testDetectProgressiveJPEG() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        XCTAssertTrue(ImageDecoder.isProgressiveJPEG(data: data)!)
    }

    func testDetectProgressiveJPEGNotEnoughData() {
        let data = Test.data(name: "progressive", extension: "jpeg")
        XCTAssertNil(ImageDecoder.isProgressiveJPEG(data: data[0...30]))
        XCTAssertNil(ImageDecoder.isProgressiveJPEG(data: data[0...3]))
        XCTAssertNil(ImageDecoder.isProgressiveJPEG(data: Data()))

        // Just before the first scan
        XCTAssertNil(ImageDecoder.isProgressiveJPEG(data: data[0...358]))
        XCTAssertTrue(ImageDecoder.isProgressiveJPEG(data: data[0...359])!)
    }

    func testDetectProgressiveJPEGActuallyBaseline() {
        let data = Test.data(name: "baseline", extension: "jpeg")
        XCTAssertFalse(ImageDecoder.isProgressiveJPEG(data: data)!)
    }

    func testDetectProgressiveJPEGActuallyPNG() {
        let data = Test.data(name: "fixture", extension: "png")
        XCTAssertFalse(ImageDecoder.isProgressiveJPEG(data: data)!)
        XCTAssertFalse(ImageDecoder.isProgressiveJPEG(data: data[0...2])!)
    }
}

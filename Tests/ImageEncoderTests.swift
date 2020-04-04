// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

final class ImageEncoderTests: XCTestCase {
    func testEncodeImage() throws {
        // Given
        let image = Test.image
        let encoder = ImageEncoders.Default()

        // When
        let data = try XCTUnwrap(encoder.encode(image))

        // Then
        XCTAssertEqual(ImageType(data), .jpeg)
    }

    func testEncodeImagePNGNonTransparent() throws {
        // Given
        let image = Test.image(named: "fixture", extension: "png")
        let encoder = ImageEncoders.Default()

        // When
        let data = try XCTUnwrap(encoder.encode(image))

        // Then
        XCTAssertEqual(ImageType(data), .jpeg)
    }

    func testEncodeImagePNGTransparent() throws {
        // Given
        let image = Test.image(named: "swift", extension: "png")
        let encoder = ImageEncoders.Default()

        // When
        let data = try XCTUnwrap(encoder.encode(image))

        // Then
        XCTAssertEqual(ImageType(data), .png)
    }

    func testPrefersHEIF() throws {
        // Given
        let image = Test.image
        var encoder = ImageEncoders.Default()
        encoder.isHEIFPreferred = true

        // When
        let data = try XCTUnwrap(encoder.encode(image))

        // Then
        XCTAssertNil(ImageType(data)) // TODO: update when HEIF support is added

    }

    // MARK: - Misc

    func testIsOpaqueWithOpaquePNG() {
        let image = Test.image(named: "fixture", extension: "png")
        XCTAssertTrue(image.cgImage!.isOpaque)
    }

    func testIsOpaqueWithTransparentPNG() {
        let image = Test.image(named: "swift", extension: "png")
        XCTAssertFalse(image.cgImage!.isOpaque)
    }
}

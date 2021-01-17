// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

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

    func testEncodeImagePNGOpaque() throws {
        // Given
        let image = Test.image(named: "fixture", extension: "png")
        let encoder = ImageEncoders.Default()

        // When
        let data = try XCTUnwrap(encoder.encode(image))

        // Then
        #if os(macOS)
        // It seems that on macOS, NSImage created from png has an alpha
        // component regardless of whether the input image has it.
        XCTAssertEqual(ImageType(data), .png)
        #else
        XCTAssertEqual(ImageType(data), .jpeg)
        #endif
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

    #if os(iOS) || os(tvOS)

    func testEncodeCoreImageBackedImage() throws {
        // Given
        let image = ImageProcessors.GaussianBlur()
            .process(Test.image)!
        let encoder = ImageEncoders.Default()

        // When
        let data = try XCTUnwrap(encoder.encode(image))

        // Then encoded as PNG because GaussianBlur produces
        // images with alpha channel
        XCTAssertEqual(ImageType(data), .png)
    }

    #endif

    // MARK: - Misc

    func testIsOpaqueWithOpaquePNG() {
        let image = Test.image(named: "fixture", extension: "png")
        #if os(macOS)
        XCTAssertFalse(image.cgImage!.isOpaque)
        #else
        XCTAssertTrue(image.cgImage!.isOpaque)
        #endif
    }

    func testIsOpaqueWithTransparentPNG() {
        let image = Test.image(named: "swift", extension: "png")
        XCTAssertFalse(image.cgImage!.isOpaque)
    }
}

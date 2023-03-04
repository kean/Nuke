// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

class ImageThumbnailTest: XCTestCase {

    func testThatImageIsResized() throws {
        // WHEN
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let output = try XCTUnwrap(options.makeThumbnail(with: Test.data))

        // THEN
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 400, height: 300))
    }

    func testThatImageIsResizedToFill() throws {
        // Given
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFill)

        // When
        let output = try XCTUnwrap(options.makeThumbnail(with: Test.data))

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 533, height: 400))
    }

    func testThatImageIsResizedToFillPNG() throws {
        // Given
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 180, height: 180), unit: .pixels, contentMode: .aspectFill)

        // When
        // Input: 640 × 360
        let output = try XCTUnwrap(makeThumbnail(data: Test.data(name: "fixture", extension: "png"), options: options))

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 320, height: 180))
    }

    func testThatImageIsResizedToFit() throws {
        // Given
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFit)

        // When
        let output = try XCTUnwrap(options.makeThumbnail(with: Test.data))

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 400, height: 300))
    }

    func testThatImageIsResizedToFitPNG() throws {
        // Given
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 160, height: 160), unit: .pixels, contentMode: .aspectFit)

        // When
        // Input: 640 × 360
        let output = try XCTUnwrap(options.makeThumbnail(with: Test.data(name: "fixture", extension: "png")))

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 160, height: 90))
    }

#if os(iOS) || os(tvOS) || os(watchOS)
    func testResizeImageWithOrientationRight() throws {
        // Given an image with `right` orientation. From the user perspective,
        // the image a landscape image with s size 640x480px. The raw pixel
        // data, on the other hand, is 480x640px.
        let input = try XCTUnwrap(Test.data(name: "left-orientation", extension: "jpeg"))
        XCTAssertEqual(PlatformImage(data: input)?.imageOrientation, .right)

        // When we resize the image to fit 320x480px frame, we expect the processor
        // to take image orientation into the account and produce a 320x240px.
        let options = ImageRequest.ThumbnailOptions(size: CGSize(width: 320, height: 1000), unit: .pixels, contentMode: .aspectFit)
        let output = try XCTUnwrap(options.makeThumbnail(with: input))

        // Then the output thumbnail is rotated
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 320, height: 240))
        XCTAssertEqual(output.imageOrientation, .up)
        // Then the image is resized according to orientation
        XCTAssertEqual(output.size, CGSize(width: 320, height: 240))
    }
#endif
}

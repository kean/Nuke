// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

class ImageProcessorsRoundedCornersTests: XCTestCase {

    func _testThatCornerRadiusIsAdded() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.RoundedCorners(radius: 12, unit: .pixels)

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then
        let expected = Test.image(named: "s-rounded-corners.png")
        XCTAssertEqualImages(output, expected)
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 200, height: 150))
    }

    func _testThatBorderIsAdded() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let border = ImageProcessingOptions.Border(color: .red, width: 4, unit: .pixels)
        let processor = ImageProcessors.RoundedCorners(radius: 12, unit: .pixels, border: border)

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then
        let expected = Test.image(named: "s-rounded-corners-border.png")
        XCTAssertEqualImages(output, expected)
    }

    func testExtendedColorSpaceSupport() throws {
        // Given
        let input = Test.image(named: "image-p3", extension: "jpg")
        let processor = ImageProcessors.RoundedCorners(radius: 12, unit: .pixels)

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then image is resized but isn't cropped
        let colorSpace = try XCTUnwrap(output.cgImage?.colorSpace)
        XCTAssertTrue(colorSpace.isWideGamutRGB)
    }

    func testEqualIdentifiers() {
        XCTAssertEqual(
            ImageProcessors.RoundedCorners(radius: 16).identifier,
            ImageProcessors.RoundedCorners(radius: 16).identifier
        )
        XCTAssertEqual(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels).identifier,
            ImageProcessors.RoundedCorners(radius: 16 / Screen.scale, unit: .points).identifier
        )
        XCTAssertEqual(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier,
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier
        )
    }

    func testNotEqualIdentifiers() {
        XCTAssertNotEqual(
            ImageProcessors.RoundedCorners(radius: 16).identifier,
            ImageProcessors.RoundedCorners(radius: 8).identifier
        )
        if Screen.scale == 1 {
            XCTAssertEqual(
                ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier,
                ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).identifier
            )
            XCTAssertNotEqual(
                ImageProcessors.RoundedCorners(radius: 32, unit: .pixels, border: .init(color: .red)).identifier,
                ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).identifier
            )
        } else {
            XCTAssertNotEqual(
                ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier,
                ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).identifier
            )
        }
        XCTAssertNotEqual(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier,
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .blue)).identifier
        )
    }

    func testEqualHashableIdentifiers() {
        XCTAssertEqual(
            ImageProcessors.RoundedCorners(radius: 16).hashableIdentifier,
            ImageProcessors.RoundedCorners(radius: 16).hashableIdentifier
        )
        XCTAssertEqual(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels).hashableIdentifier,
            ImageProcessors.RoundedCorners(radius: 16 / Screen.scale, unit: .points).hashableIdentifier
        )
        XCTAssertEqual(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier,
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier
        )
    }

    func testNotEqualHashableIdentifiers() {
        XCTAssertNotEqual(
            ImageProcessors.RoundedCorners(radius: 16).hashableIdentifier,
            ImageProcessors.RoundedCorners(radius: 8).hashableIdentifier
        )
        if Screen.scale == 1 {
            XCTAssertEqual(
                ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier,
                ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).hashableIdentifier
            )
            XCTAssertNotEqual(
                ImageProcessors.RoundedCorners(radius: 32, unit: .pixels, border: .init(color: .red)).hashableIdentifier,
                ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).hashableIdentifier
            )
        } else {
            XCTAssertNotEqual(
                ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier,
                ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).hashableIdentifier
            )
        }
        XCTAssertNotEqual(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier,
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .blue)).hashableIdentifier
        )
    }

    func testDescription() {
        // Given
        let processor = ImageProcessors.RoundedCorners(radius: 16, unit: .pixels)

        // Then
        XCTAssertEqual(processor.description, "RoundedCorners(radius: 16.0 pixels, border: nil)")
    }

    func testDescriptionWithBorder() {
        // Given
        let processor = ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red, width: 2, unit: .pixels))

        // Then
        XCTAssertEqual(processor.description, "RoundedCorners(radius: 16.0 pixels, border: Border(color: #FF0000, width: 2.0 pixels))")
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS)
class ImageProcessorsRoundedCornersTests: XCTestCase {

    func testThatCornerRadiusIsAdded() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.RoundedCorners(radius: 12, unit: .pixels)

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then
        XCTAssertEqualImages(output, Test.image(named: "s-rounded-corners.png"))
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 200, height: 150))
    }

    func testThatBorderIsAdded() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let border = ImageProcessingOptions.Border(color: .red, width: 4, unit: .pixels)
        let processor = ImageProcessors.RoundedCorners(radius: 12, unit: .pixels, border: border)

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then
        XCTAssertEqualImages(output, Test.image(named: "s-rounded-corners-border.png"))
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
        XCTAssertNotEqual(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier,
            ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).identifier
        )
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
        XCTAssertNotEqual(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier,
            ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).hashableIdentifier
        )
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
        let processor = ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red))

        // Then
        XCTAssertEqual(processor.description, "RoundedCorners(radius: 16.0 pixels, border: Border(color: #FF0000, width: 2.0 pixels))")
    }
}
#endif

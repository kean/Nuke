// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS)
class ImageProcessorsCircleTests: XCTestCase {

    func testThatImageIsCroppedToSquareAutomatically() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.Circle()

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then
        let cgImage = try XCTUnwrap(output.cgImage, "Expected image to be backed by CGImage")
        XCTAssertEqual(cgImage.width, 150)
        XCTAssertEqual(cgImage.height, 150)
        XCTAssertEqualImages(output, Test.image(named: "s-circle.png"))
    }

    func testThatBorderIsAdded() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let border = ImageProcessingOptions.Border(color: .red, width: 4, unit: .pixels)
        let processor = ImageProcessors.Circle(border: border)

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then
        let cgImage = try XCTUnwrap(output.cgImage, "Expected image to be backed by CGImage")
        XCTAssertEqual(cgImage.width, 150)
        XCTAssertEqual(cgImage.height, 150)
        XCTAssertEqualImages(output, Test.image(named: "s-circle-border.png"))
    }

    func testIdentifierEqual() throws {
        XCTAssertEqual(
            ImageProcessors.Circle().identifier,
            ImageProcessors.Circle().identifier
        )
        XCTAssertEqual(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).identifier,
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).identifier
        )
        XCTAssertEqual(
            ImageProcessors.Circle(border: .init(color: .red, width: 4, unit: .pixels)).identifier,
            ImageProcessors.Circle(border: .init(color: .red, width: 4 / Screen.scale, unit: .points)).identifier
        )
    }

    func testIdentifierNotEqual() throws {
        XCTAssertNotEqual(
            ImageProcessors.Circle().identifier,
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).identifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).identifier,
            ImageProcessors.Circle(border: .init(color: .red, width: 4, unit: .pixels)).identifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).identifier,
            ImageProcessors.Circle(border: .init(color: .blue, width: 2, unit: .pixels)).identifier
        )
    }

    func testHashableIdentifierEqual() throws {
        XCTAssertEqual(
            ImageProcessors.Circle().hashableIdentifier,
            ImageProcessors.Circle().hashableIdentifier
        )
        XCTAssertEqual(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).hashableIdentifier,
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).hashableIdentifier
        )
        XCTAssertEqual(
            ImageProcessors.Circle(border: .init(color: .red, width: 4, unit: .pixels)).hashableIdentifier,
            ImageProcessors.Circle(border: .init(color: .red, width: 4 / Screen.scale, unit: .points)).hashableIdentifier
        )
    }

    func testHashableNotEqual() throws {
        XCTAssertNotEqual(
            ImageProcessors.Circle().identifier,
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).hashableIdentifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).hashableIdentifier,
            ImageProcessors.Circle(border: .init(color: .red, width: 4, unit: .pixels)).hashableIdentifier
        )
        XCTAssertNotEqual(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).hashableIdentifier,
            ImageProcessors.Circle(border: .init(color: .blue, width: 2, unit: .pixels)).hashableIdentifier
        )
    }

    func testDescription() {
        // Given
        let processor = ImageProcessors.Circle(border: .init(color: .blue, width: 2, unit: .pixels))

        // Then
        XCTAssertEqual(processor.description, "Circle(border: Border(color: #0000FF, width: 2.0))")
    }

    func testColorToHex() {
        // Given
        let color = UIColor.red

        // Then
        XCTAssertEqual(color.hex, "#FF0000")
    }
}
#endif

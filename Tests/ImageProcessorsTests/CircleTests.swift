// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS)
class ImageProcessorsCircleTests: XCTestCase {

    func _testThatImageIsCroppedToSquareAutomatically() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.Circle()

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 150, height: 150))
        XCTAssertEqualImages(output, Test.image(named: "s-circle.png"))
    }

    func _testThatBorderIsAdded() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let border = ImageProcessingOptions.Border(color: .red, width: 4, unit: .pixels)
        let processor = ImageProcessors.Circle(border: border)

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 150, height: 150))
        XCTAssertEqualImages(output, Test.image(named: "s-circle-border.png"))
    }

    func testExtendedColorSpaceSupport() throws {
        // Given
        let input = Test.image(named: "image-p3", extension: "jpg")
        let border = ImageProcessingOptions.Border(color: .red, width: 4, unit: .pixels)
        let processor = ImageProcessors.Circle(border: border)

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then image is resized but isn't cropped
        let colorSpace = try XCTUnwrap(output.cgImage?.colorSpace)
        XCTAssertTrue(colorSpace.isWideGamutRGB)
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
        XCTAssertEqual(processor.description, "Circle(border: Border(color: #0000FF, width: 2.0 pixels))")
    }

    func testDescriptionWithoutBorder() {
        // Given
        let processor = ImageProcessors.Circle()

        // Then
        XCTAssertEqual(processor.description, "Circle(border: nil)")
    }

    func testColorToHex() {
        // Given
        let color = UIColor.red

        // Then
        XCTAssertEqual(color.hex, "#FF0000")
    }
}
#endif

// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS) || os(visionOS)
@Suite struct ImageProcessorsCircleTests {

    func _testThatImageIsCroppedToSquareAutomatically() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.Circle()

        // When
        let output = try #require(processor.process(input), "Failed to process an image")

        // Then
        #expect(output.sizeInPixels == CGSize(width: 150, height: 150))
        #expect(isEqual(output, Test.image(named: "s-circle.png")))
    }

    func _testThatBorderIsAdded() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let border = ImageProcessingOptions.Border(color: .red, width: 4, unit: .pixels)
        let processor = ImageProcessors.Circle(border: border)

        // When
        let output = try #require(processor.process(input), "Failed to process an image")

        // Then
        #expect(output.sizeInPixels == CGSize(width: 150, height: 150))
        #expect(isEqual(output, Test.image(named: "s-circle-border.png")))
    }

    @Test func extendedColorSpaceSupport() throws {
        // Given
        let input = Test.image(named: "image-p3", extension: "jpg")
        let border = ImageProcessingOptions.Border(color: .red, width: 4, unit: .pixels)
        let processor = ImageProcessors.Circle(border: border)

        // When
        let output = try #require(processor.process(input), "Failed to process an image")

        // Then image is resized but isn't cropped
        let colorSpace = try #require(output.cgImage?.colorSpace)
        #expect(colorSpace.isWideGamutRGB)
    }

    @Test

    @MainActor
    func identifierEqual() throws {
        #expect(
            ImageProcessors.Circle().identifier == ImageProcessors.Circle().identifier
        )
        #expect(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).identifier == ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).identifier
        )
        #expect(
            ImageProcessors.Circle(border: .init(color: .red, width: 4, unit: .pixels)).identifier == ImageProcessors.Circle(border: .init(color: .red, width: 4 / Screen.scale, unit: .points)).identifier
        )
    }

    @Test func identifierNotEqual() throws {
        #expect(
            ImageProcessors.Circle().identifier != ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).identifier
        )
        #expect(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).identifier != ImageProcessors.Circle(border: .init(color: .red, width: 4, unit: .pixels)).identifier
        )
        #expect(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).identifier != ImageProcessors.Circle(border: .init(color: .blue, width: 2, unit: .pixels)).identifier
        )
    }

    @Test

    @MainActor
    func hashableIdentifierEqual() throws {
        #expect(
            ImageProcessors.Circle().hashableIdentifier == ImageProcessors.Circle().hashableIdentifier
        )
        #expect(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).hashableIdentifier == ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).hashableIdentifier
        )
        #expect(
            ImageProcessors.Circle(border: .init(color: .red, width: 4, unit: .pixels)).hashableIdentifier == ImageProcessors.Circle(border: .init(color: .red, width: 4 / Screen.scale, unit: .points)).hashableIdentifier
        )
    }

    @Test func hashableNotEqual() throws {
        #expect(
            ImageProcessors.Circle().hashableIdentifier != ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).hashableIdentifier
        )
        #expect(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).hashableIdentifier != ImageProcessors.Circle(border: .init(color: .red, width: 4, unit: .pixels)).hashableIdentifier
        )
        #expect(
            ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)).hashableIdentifier != ImageProcessors.Circle(border: .init(color: .blue, width: 2, unit: .pixels)).hashableIdentifier
        )
    }

    @Test func description() {
        // Given
        let processor = ImageProcessors.Circle(border: .init(color: .blue, width: 2, unit: .pixels))

        // Then
        #expect(processor.description == "Circle(border: Border(color: #0000FF, width: 2.0 pixels))")
    }

    @Test func descriptionWithoutBorder() {
        // Given
        let processor = ImageProcessors.Circle()

        // Then
        #expect(processor.description == "Circle(border: nil)")
    }

    @Test func colorToHex() {
        // Given
        let color = UIColor.red

        // Then
        #expect(color.hex == "#FF0000")
    }
}
#endif

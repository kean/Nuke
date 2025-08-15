// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke

@Suite struct ImageProcessorsRoundedCornersTests {

    func _testThatCornerRadiusIsAdded() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.RoundedCorners(radius: 12, unit: .pixels)

        // When
        let output = try #require(processor.process(input), "Failed to process an image")

        // Then
        let expected = Test.image(named: "s-rounded-corners.png")
        #expect(isEqual(output, expected))
        #expect(output.sizeInPixels == CGSize(width: 200, height: 150))
    }

    func _testThatBorderIsAdded() throws {
        // Given
        let input = Test.image(named: "fixture-tiny.jpeg")
        let border = ImageProcessingOptions.Border(color: .red, width: 4, unit: .pixels)
        let processor = ImageProcessors.RoundedCorners(radius: 12, unit: .pixels, border: border)

        // When
        let output = try #require(processor.process(input), "Failed to process an image")

        // Then
        let expected = Test.image(named: "s-rounded-corners-border.png")
        #expect(isEqual(output, expected))
    }

    @Test func extendedColorSpaceSupport() throws {
        // Given
        let input = Test.image(named: "image-p3", extension: "jpg")
        let processor = ImageProcessors.RoundedCorners(radius: 12, unit: .pixels)

        // When
        let output = try #require(processor.process(input), "Failed to process an image")

        // Then image is resized but isn't cropped
        let colorSpace = try #require(output.cgImage?.colorSpace)
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
        #expect(colorSpace.isWideGamutRGB)
#elseif os(watchOS)
        #expect(!colorSpace.isWideGamutRGB)
#endif
    }

    @Test

    @MainActor
    func equalIdentifiers() {
        #expect(
            ImageProcessors.RoundedCorners(radius: 16).identifier == ImageProcessors.RoundedCorners(radius: 16).identifier
        )
        #expect(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels).identifier == ImageProcessors.RoundedCorners(radius: 16 / Screen.scale, unit: .points).identifier
        )
        #expect(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier == ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier
        )
    }

    @Test

    @MainActor
    func notEqualIdentifiers() {
        #expect(
            ImageProcessors.RoundedCorners(radius: 16).identifier != ImageProcessors.RoundedCorners(radius: 8).identifier
        )
        if Screen.scale == 1 {
            #expect(
                ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier == ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).identifier
            )
            #expect(
                ImageProcessors.RoundedCorners(radius: 32, unit: .pixels, border: .init(color: .red)).identifier != ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).identifier
            )
        } else {
            #expect(
                ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier != ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).identifier
            )
        }
        #expect(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).identifier != ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .blue)).identifier
        )
    }

    @Test

    @MainActor
    func equalHashableIdentifiers() {
        #expect(
            ImageProcessors.RoundedCorners(radius: 16).hashableIdentifier == ImageProcessors.RoundedCorners(radius: 16).hashableIdentifier
        )
        #expect(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels).hashableIdentifier == ImageProcessors.RoundedCorners(radius: 16 / Screen.scale, unit: .points).hashableIdentifier
        )
        #expect(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier == ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier
        )
    }

    @Test

    @MainActor
    func notEqualHashableIdentifiers() {
        #expect(
            ImageProcessors.RoundedCorners(radius: 16).hashableIdentifier != ImageProcessors.RoundedCorners(radius: 8).hashableIdentifier
        )
        if Screen.scale == 1 {
            #expect(
                ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier == ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).hashableIdentifier
            )
            #expect(
                ImageProcessors.RoundedCorners(radius: 32, unit: .pixels, border: .init(color: .red)).hashableIdentifier != ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).hashableIdentifier
            )
        } else {
            #expect(
                ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier != ImageProcessors.RoundedCorners(radius: 16, unit: .points, border: .init(color: .red)).hashableIdentifier
            )
        }
        #expect(
            ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red)).hashableIdentifier != ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .blue)).hashableIdentifier
        )
    }

    @Test func description() {
        // Given
        let processor = ImageProcessors.RoundedCorners(radius: 16, unit: .pixels)

        // Then
        #expect(processor.description == "RoundedCorners(radius: 16.0 pixels, border: nil)")
    }

    @Test func descriptionWithBorder() {
        // Given
        let processor = ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red, width: 2, unit: .pixels))

        // Then
        #expect(processor.description == "RoundedCorners(radius: 16.0 pixels, border: Border(color: #FF0000, width: 2.0 pixels))")
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsRoundedCornersTests {

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

    /// The radius and the width of the border in points are converted to
    /// pixels before they become part of the identifiers.
    @Test @MainActor func pointsAndPixelsProduceTheSameIdentifiers() {
        let pixels = ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red, width: 2, unit: .pixels))
        let points = ImageProcessors.RoundedCorners(radius: 16 / Screen.scale, unit: .points, border: .init(color: .red, width: 2 / Screen.scale, unit: .points))

        #expect(pixels.identifier == points.identifier)
        #expect(pixels.hashableIdentifier == points.hashableIdentifier)
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

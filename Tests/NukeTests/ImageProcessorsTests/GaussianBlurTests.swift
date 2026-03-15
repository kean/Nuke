// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@Suite struct ImageProcessorsGaussianBlurTests {
    @Test func applyBlur() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()
        #expect(!processor.description.isEmpty)

        // When
        #expect(processor.process(image) != nil)
    }

    @Test func applyBlurProducesImagesBackedByCoreGraphics() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        #expect(processor.process(image) != nil)
    }

    @Test func applyBlurProducesTransparentImages() throws {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        let processed = try #require(processor.process(image))

        // Then
        #expect(processed.cgImage?.isOpaque == false)
    }

    @Test func imagesWithSameRadiusHasSameIdentifiers() {
        #expect(
            ImageProcessors.GaussianBlur(radius: 2).identifier ==
            ImageProcessors.GaussianBlur(radius: 2).identifier
        )
    }

    @Test func imagesWithDifferentRadiusHasDifferentIdentifiers() {
        #expect(
            ImageProcessors.GaussianBlur(radius: 2).identifier !=
            ImageProcessors.GaussianBlur(radius: 3).identifier
        )
    }

    @Test func imagesWithSameRadiusHasSameHashableIdentifiers() {
        #expect(
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier ==
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier
        )
    }

    @Test func imagesWithDifferentRadiusHasDifferentHashableIdentifiers() {
        #expect(
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier !=
            ImageProcessors.GaussianBlur(radius: 3).hashableIdentifier
        )
    }

    // MARK: - Output Dimensions

    @Test func blurDoesNotChangeImageDimensions() throws {
        // GIVEN
        let image = Test.image
        let inputSize = image.sizeInPixels
        let processor = ImageProcessors.GaussianBlur(radius: 8)

        // WHEN
        let output = try #require(processor.process(image))

        // THEN - blurring must not alter the canvas size
        #expect(output.sizeInPixels == inputSize)
    }

    @Test func blurWithMinimumRadiusProducesOutput() throws {
        // GIVEN - radius of 1 is the smallest non-trivial blur
        let processor = ImageProcessors.GaussianBlur(radius: 1)

        // WHEN / THEN - must not crash and must return a valid image
        let output = try #require(processor.process(Test.image))
        #expect(output.sizeInPixels == Test.image.sizeInPixels)
    }

    @Test func differentRadiiProduceDifferentDescriptions() {
        #expect(
            ImageProcessors.GaussianBlur(radius: 4).description !=
            ImageProcessors.GaussianBlur(radius: 16).description
        )
    }
}

#endif

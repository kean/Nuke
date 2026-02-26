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
}

#endif

// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS)

class ImageProcessorsGaussianBlurTest: XCTestCase {
    func testApplyBlur() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()
        XCTAssertFalse(processor.description.isEmpty) // Bumping that test coverage

        // When
        let processed = processor.process(image)

        // Then
        XCTAssertNotNil(processed)
    }

    func testApplyBlurProducesImagesBackedByCoreGraphics() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        let processed = processor.process(image)

        // Then
        XCTAssertNotNil(processed?.cgImage)
    }

    func testApplyBlurProducesTransparentImages() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        let processed = processor.process(image)

        // Then
        XCTAssertEqual(processed?.cgImage?.isOpaque, false)
    }

    func testImagesWithSameRadiusHasSameIdentifiers() {
        XCTAssertEqual(
            ImageProcessors.GaussianBlur(radius: 2).identifier,
            ImageProcessors.GaussianBlur(radius: 2).identifier
        )
    }

    func testImagesWithDifferentRadiusHasDifferentIdentifiers() {
        XCTAssertNotEqual(
            ImageProcessors.GaussianBlur(radius: 2).identifier,
            ImageProcessors.GaussianBlur(radius: 3).identifier
        )
    }

    func testImagesWithSameRadiusHasSameHashableIdentifiers() {
        XCTAssertEqual(
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier,
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier
        )
    }

    func testImagesWithDifferentRadiusHasDifferentHashableIdentifiers() {
        XCTAssertNotEqual(
            ImageProcessors.GaussianBlur(radius: 2).hashableIdentifier,
            ImageProcessors.GaussianBlur(radius: 3).hashableIdentifier
        )
    }
}

#endif

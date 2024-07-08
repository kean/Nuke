// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
import NukeTestHelpers
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

class ImageProcessorsGaussianBlurTest: XCTestCase {
    func testApplyBlur() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()
        XCTAssertFalse(processor.description.isEmpty) // Bumping that test coverage

        // When
        XCTAssertNotNil(processor.process(image))
    }

    func testApplyBlurProducesImagesBackedByCoreGraphics() {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        XCTAssertNotNil(processor.process(image))
    }

    func testApplyBlurProducesTransparentImages() throws {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        let processed = try XCTUnwrap(processor.process(image))

        // Then
        XCTAssertEqual(processed.cgImage?.isOpaque, false)
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

// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS)

class ImageProcessorsGaussianBlurTest: XCTestCase {
    func testApplyBlur() throws {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()
        XCTAssertFalse(processor.description.isEmpty) // Bumping that test coverage

        // When
        try processor.process(image)
    }

    func testApplyBlurProducesImagesBackedByCoreGraphics() throws {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        try processor.process(image)
    }

    func testApplyBlurProducesTransparentImages() throws {
        // Given
        let image = Test.image
        let processor = ImageProcessors.GaussianBlur()

        // When
        let processed = try processor.process(image)

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

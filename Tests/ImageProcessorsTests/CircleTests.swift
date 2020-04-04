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
        let processor = ImageProcessors.Circle()

        // When
        let image = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")
        let cgImage = try XCTUnwrap(image.cgImage, "Expected image to be backed by CGImage")

        // Then
        XCTAssertEqual(cgImage.width, 480)
        XCTAssertEqual(cgImage.height, 480)
    }
}
#endif

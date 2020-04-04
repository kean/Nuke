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
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.Circle()

        // When
        let output = try XCTUnwrap(processor.process(input), "Failed to process an image")

        // Then
        let cgImage = try XCTUnwrap(output.cgImage, "Expected image to be backed by CGImage")
        XCTAssertEqual(cgImage.width, 150)
        XCTAssertEqual(cgImage.height, 150)
        XCTAssertEqualImages(output, Test.image(named: "s-circle.png"))
    }
}
#endif

// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

#if os(iOS) || os(tvOS)
class ImageProcessorsRoundedCornersTests: XCTestCase {

    /// We don't check the actual output yet, just that it compiles and that
    /// _some_ output is produced.
    func testThatImageIsProduced() throws {
        // Given
        let processor = ImageProcessors.RoundedCorners(radius: 12)

        // When
        let image = try XCTUnwrap(processor.process(Test.image), "Failed to process an image")
        let cgImage = try XCTUnwrap(image.cgImage, "Expected image to be backed by CGImage")

        // Then
        XCTAssertEqual(cgImage.width, 640)
        XCTAssertEqual(cgImage.height, 480)
    }
}
#endif

// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

class ImageThumbnailTest: XCTestCase {

    func testThatImageIsResized() throws {
        // WHEN
        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let output = try XCTUnwrap(makeThumbnail(data: Test.data, options: options))

        // THEN
        XCTAssertEqual(output.sizeInPixels, CGSize(width: 400, height: 300))
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImageProcessorsProtocolExtensionsTests: XCTestCase {

    func testPassingProcessorsUsingProtocolExtensions() throws {
        // Just make sure it compiles
        _ = ImageRequest(url: nil, processors: [.resize(width: 100)])
    }
}

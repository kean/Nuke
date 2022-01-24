// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

#if swift(>=5.5)
class ImageProcessorsProtocolExtensionsTests: XCTestCase {

    func testPassingProcessorsUsingProtocolExtensions() throws {
        // Just make sure it compiles
        let _ = ImageRequest(url: nil, processors: [.resize(width: 100)])
    }
}
#endif

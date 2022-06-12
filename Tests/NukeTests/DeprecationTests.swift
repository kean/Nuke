// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class NewImageRequestTests: XCTestCase {
    // The compiler picks up the new version
    func testInit() {
        _ = ImageRequest(url: Test.url)
        _ = ImageRequest(url: Test.url, processors: [])
        _ = ImageRequest(url: Test.url, processors: [])
        _ = ImageRequest(url: Test.url, priority: .high)
        _ = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
    }
}

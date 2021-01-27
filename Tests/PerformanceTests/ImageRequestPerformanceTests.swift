// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImageRequestPerformanceTests: XCTestCase {
    func testStoringRequestInCollections() {
        let urls = (0..<200_000).map { _ in return URL(string: "http://test.com/\(rnd(200))")! }
        let requests = urls.map { ImageRequest(url: $0) }

        measure {
            var array = [ImageRequest]()
            for request in requests {
                array.append(request)
            }
        }
    }
}

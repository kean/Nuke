// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke

@Suite
struct ImageRequestPerformanceTests {
    @Test
    func storingRequestInCollections() {
        let urls = (0..<200_000).map { _ in URL(string: "http://test.com/\(Int.random(in: 0..<200))")! }
        let requests = urls.map { ImageRequest(url: $0) }

        measure {
            var array = [ImageRequest]()
            for request in requests {
                array.append(request)
            }
        }
    }
}

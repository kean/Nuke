// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImageCachePerformanceTests: XCTestCase {
    func testCacheWrite() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())

        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(500))")! }
        let requests = urls.map { ImageRequest(url: $0) }

        measure {
            for request in requests {
                cache[request] = image
            }
        }
    }

    func testCacheHit() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())

        for index in 0..<200 {
            cache[ImageRequest(url: URL(string: "http://test.com/\(index)")!)] = image
        }

        var hits = 0

        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(200))")! }
        let requests = urls.map { ImageRequest(url: $0) }

        measure {
            for request in requests {
                if cache[request] != nil {
                    hits += 1
                }
            }
        }

        print("hits: \(hits)")
    }

    func testCacheMiss() {
        let cache = ImageCache()

        var misses = 0

        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(200))")! }
        let requests = urls.map { ImageRequest(url: $0) }

        measure {
            for request in requests {
                if cache[request] != nil {
                    misses += 1
                }
            }
        }

        print("misses: \(misses)")
    }
}

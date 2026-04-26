// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke

@Suite
struct ImageCachePerformanceTests {
    @Test
    func cacheWrite() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())

        let urls = (0..<100_000).map { _ in URL(string: "http://test.com/\(Int.random(in: 0..<500))")! }
        let requests = urls.map { ImageRequest(url: $0) }

        measure {
            for request in requests {
                cache[request] = image
            }
        }
    }

    @Test
    func cacheHit() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())

        for index in 0..<2000 {
            cache[ImageRequest(url: URL(string: "http://test.com/\(index)")!)] = image
        }

        var hits = 0

        let urls = (0..<100_000).map { _ in URL(string: "http://test.com/\(Int.random(in: 0..<2000))")! }
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

    @Test
    func cacheMiss() {
        let cache = ImageCache()

        var misses = 0

        let urls = (0..<100_000).map { _ in URL(string: "http://test.com/\(Int.random(in: 0..<200))")! }
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

    @Test
    func cacheReplacement() {
        let cache = ImageCache()
        let request = Test.request
        let image = Test.container

        measure {
            for _ in 0..<100_000 {
                cache[request] = image
            }
        }
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ManagerPerformanceTests: XCTestCase {
    func testManagerMainThreadPerformance() {
        let view = ImageView()

        let urls = (0..<25_000).map { _ in return URL(string: "http://test.com/\(rnd(5000))")! }
        
        measure {
            for url in urls {
                Nuke.loadImage(with: url, into: view)
            }
        }
    }
}

class ImagePipelinePerfomanceTests: XCTestCase {
    /// A very broad test that establishes how long in general it takes to load
    /// data, decode, and decomperss 50+ images. It's very useful to get a
    /// broad picture about how loader options affect perofmance.
    func testLoaderOverallPerformance() {
        let dataLoader = MockDataLoader()

        let loader = ImagePipeline {
            $0.dataLoader = dataLoader

            // This must be off for this test, because rate limiter is optimized for
            // the actual loading in the apps and not the syntetic tests like this.
            $0.isRateLimiterEnabled = false

            $0.isDeduplicationEnabled = false

            // Disables processing which takes a bulk of time.
            $0.imageProcessor = { _ in nil }
        }

        let urls = (0...3_000).map { _ in return URL(string: "http://test.com/\(rnd(500))")! }
        measure {
            expect { fulfil in
                var finished: Int = 0
                for url in urls {
                    loader.loadImage(with: url) { result in
                        finished += 1
                        if finished == urls.count {
                            fulfil()
                        }
                    }
                }
            }
            wait(10)
        }
    }
}

class CachePerformanceTests: XCTestCase {
    func testCacheWrite() {
        let cache = ImageCache()
        let image = Image()
        
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
        
        for i in 0..<200 {
            cache[ImageRequest(url: URL(string: "http://test.com/\(i)")!)] = Image()
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
                if cache[request] == nil {
                    misses += 1
                }
            }
        }
        
        print("misses: \(misses)")
    }
}

class RequestPerformanceTests: XCTestCase {
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

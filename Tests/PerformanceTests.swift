// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ManagerPerformanceTests: XCTestCase {
    func testManagerMainThreadPerformance() {
        let view = ImageView()

        let urls = (0..<25_000).map { _ in return URL(string: "http://test.com/\(rnd(5000))")! }
        
        measure {
            for url in urls {
                Manager.shared.loadImage(with: url, into: view)
            }
        }
    }
}

class LoaderPerfomanceTests: XCTestCase {
    /// A very broad test that establishes how long in general it takes to load
    /// data, decode, and decomperss 50+ images. It's very useful to get a
    /// broad picture about how loader options affect perofmance.
    func testLoaderOverallPerformance() {
        let dataLoader = MockDataLoader()
        var options = Loader.Options()
        // This must be off for this test, because rate limiter is optimized for
        // the actual loading in the apps and not the syntetic tests like this.
        options.isRateLimiterEnabled = false

        options.isDeduplicationEnabled = false

        // Disables processing which takes a bulk of time.
        options.processor = { (_,_) in nil }

        let loader = Loader(loader: dataLoader, options: options)

        let urls = (0..<1_000).map { _ in return URL(string: "http://test.com/\(rnd(500))")! }
        measure {
            expect { fulfil in
                var finished: Int = 0
                for url in urls {
                    loader.loadImage(with: url, token: nil) { result in
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
        let cache = Cache()
        let image = Image()
        
        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(500))")! }
        let requests = urls.map { Request(url: $0) }
        
        measure {
            for request in requests {
                cache[request] = image
            }
        }
    }
    
    func testCacheHit() {
        let cache = Cache()
        
        for i in 0..<200 {
            cache[Request(url: URL(string: "http://test.com/\(i)")!)] = Image()
        }
        
        var hits = 0
        
        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(200))")! }
        let requests = urls.map { Request(url: $0) }
        
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
        let cache = Cache()
        
        var misses = 0
        
        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(200))")! }
        let requests = urls.map { Request(url: $0) }
        
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
        let requests = urls.map { Request(url: $0) }

        measure {
            var array = [Request]()
            for request in requests {
                array.append(request)
            }
        }
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageViewPerformanceTests: XCTestCase {
    // This is the primary use case that we are optimizing for - loading images
    // into target, the API that majoriy of the apps are going to use.
    func testImageViewMainThreadPerformance() {
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
                    loader.loadImage(with: url) { _,_ in
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

class ImageCachePerformanceTests: XCTestCase {
    func testCacheWrite() {
        let cache = ImageCache()
        let response = ImageResponse(image: Image(), urlResponse: nil)
        
        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(500))")! }
        let requests = urls.map { ImageRequest(url: $0) }
        
        measure {
            for request in requests {
                cache.storeResponse(response, for: request)
            }
        }
    }
    
    func testCacheHit() {
        let cache = ImageCache()
        let response = ImageResponse(image: Image(), urlResponse: nil)
        
        for i in 0..<200 {
            cache.storeResponse(response, for: ImageRequest(url: URL(string: "http://test.com/\(i)")!))
        }
        
        var hits = 0
        
        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(200))")! }
        let requests = urls.map { ImageRequest(url: $0) }
        
        measure {
            for request in requests {
                if cache.cachedResponse(for: request) != nil {
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
                if cache.cachedResponse(for: request) == nil {
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

class DataCachePeformanceTests: XCTestCase {
    var cache: DataCache!

    override func setUp() {
        cache = try! DataCache(name: UUID().uuidString)
        cache._keyEncoder = {
            guard let data = $0.cString(using: .utf8) else { return "" }
            return _nuke_sha1(data, UInt32(data.count))
        }
        _ = cache["key"] // Wait till index is loaded.
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache.path)
    }

    func testMissPerformance() {
        measure {
            for idx in 0..<10_000 {
                let _ = self.cache["\(idx)"]
            }
        }
    }

    func testWritePeformance() {
        cache._test_withSuspendedIO {
            let dummy = "123".data(using: .utf8)

            // FIXME: This test no just "empty" writes, but also overwrites
            measure {
                for idx in 0..<10_000 {
                    self.cache["\(idx)"] = dummy
                }
            }
        }
    }

    func testReadPerformance() {
        cache._test_withSuspendedIO {
            for idx in 0..<10_000 {
                cache["\(idx)"] = "123".data(using: .utf8)
            }

            measure {
                for idx in 0..<10_000 {
                    let _ = self.cache["\(idx)"]
                }
            }
        }
    }

    func testReadFlushedPerformance() {
        for idx in 0..<200 {
            cache["\(idx)"] = Data(repeating: 1, count: 256 * 1024)
        }
        cache.flush()

        measure {
            for idx in 0..<200 {
                let _ = self.cache["\(idx)"]
            }
        }
    }

    func testIndexLoadingPerformance() {
        for _ in 0..<1_000 {
            // Create a realistic-looking key
            let key = "http://example.com/images/" + UUID().uuidString + ".jpeg" + "?width=150&height=300"
            cache[key] = Data(repeating: 1, count: 64 * 1024)
        }
        cache.flush()

        // FIXME: I'm not entirely sure this the measurement is accurate,
        // filesystem caching might affect performance.
        measure {
            let cache = try! DataCache(path: self.cache.path)
            let _ = cache["1"] // Wait till index is loaded.
        }
    }

    func testLRUPerformance() {
        let items: [DataCache.Entry] = (0..<10_000).map {
            let filename = cache.filename(for: "\($0)")!
            let item = DataCache.Entry(filename: filename, payload: .saved(URL(string: "file://\(filename.raw)")!))
            item.accessDate = Date().addingTimeInterval(TimeInterval(arc4random_uniform(1000)))
            item.totalFileAllocatedSize = 1
            return item
        }

        var lru = CacheAlgorithmLRU()
        lru.countLimit = 1000 // we test count limit here
        lru.trimRatio = 0.5 // 1 item should remain after trim
        lru.sizeLimit = Int.max

        measure {
            let _ = lru.discarded(items: items)
        }
    }
}


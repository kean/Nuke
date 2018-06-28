// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageViewPerformanceTests: XCTestCase {
    // This is the primary use case that we are optimizing for - loading images
    // into target, the API that majoriy of the apps are going to use.
    func testImageViewMainThreadPerformance() {
        let view = _ImageView()

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
            $0.imageProcessor = { (_, _)  in nil }
        }

        let urls = (0...3_000).map { _ in return URL(string: "http://test.com/\(rnd(500))")! }
        measure {
            let expectation = self.expectation(description: "Image loaded")
            var finished: Int = 0
            for url in urls {
                loader.loadImage(with: url) { _, _ in
                    finished += 1
                    if finished == urls.count {
                        expectation.fulfill()
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
        
        for index in 0..<200 {
            cache.storeResponse(response, for: ImageRequest(url: URL(string: "http://test.com/\(index)")!))
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
        cache = try! DataCache(name: UUID().uuidString, filenameGenerator: {
            guard let data = $0.cString(using: .utf8) else { return "" }
            return _nuke_sha1(data, UInt32(data.count))
        })
        _ = cache["key"] // Wait till index is loaded.
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache.path)
    }

    func testReadFlushedPerformance() {
        for idx in 0..<1000 {
            cache["\(idx)"] = Data(repeating: 1, count: 256 * 1024)
        }
        cache.flush()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        measure {
            for idx in 0..<1000 {
                queue.addOperation {
                    _ = self.cache["\(idx)"]
                }
            }
            queue.waitUntilAllOperationsAreFinished()
        }
    }
}

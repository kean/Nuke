// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ImageViewPerformanceTests: XCTestCase {
    private let dummyCacheRequest = ImageRequest(url: URL(string: "http://test.com/9999999)")!, processors: [ImageProcessor.Resize(size: CGSize(width: 2, height: 2))])

    override func setUp() {
        // Store something in memory cache to avoid going through an optimized empty Dictionary path
        let response = ImageResponse(image: Image(), urlResponse: nil)
        ImagePipeline.shared.configuration.imageCache?.storeResponse(response, for: dummyCacheRequest)
    }

    override func tearDown() {
        ImagePipeline.shared.configuration.imageCache?.removeResponse(for: dummyCacheRequest)
    }

    // This is the primary use case that we are optimizing for - loading images
    // into target, the API that majoriy of the apps are going to use.
    func testImageViewMainThreadPerformance() {
        let view = _ImageView()

        let urls = (0..<25_000).map { _ in return URL(string: "http://test.com/1)")! }

        measure {
            for url in urls {
                loadImage(with: url, into: view)
            }
        }
    }

    func testImageViewMainThreadPerformanceWithProcessor() {
        let view = _ImageView()

        let urls = (0..<25_000).map { _ in return URL(string: "http://test.com/1)")! }

        measure {
            for url in urls {
                let request = ImageRequest(url: url, processors: [ImageProcessor.Resize(size: CGSize(width: 1, height: 1))])
                loadImage(with: request, into: view)
            }
        }
    }

    func testImageViewMainThreadPerformanceWithProcessorAndSimilarImageInCache() {
        let view = _ImageView()

        let urls = (0..<25_000).map { _ in return URL(string: "http://test.com/9999999)")! }

        measure {
            for url in urls {
                let request = ImageRequest(url: url, processors: [ImageProcessor.Resize(size: CGSize(width: 1, height: 1))])
                loadImage(with: request, into: view)
            }
        }
    }
}

class ImagePipelinePerfomanceTests: XCTestCase {
    /// A very broad test that establishes how long in general it takes to load
    /// data, decode, and decomperss 50+ images. It's very useful to get a
    /// broad picture about how loader options affect perofmance.
    func testLoaderOverallPerformance() {
        let pipeline = ImagePipeline {
            $0.imageCache = nil

            $0.dataLoader = MockDataLoader()

            $0.isDecompressionEnabled = false

            // This must be off for this test, because rate limiter is optimized for
            // the actual loading in the apps and not the syntetic tests like this.
            $0.isRateLimiterEnabled = false
        }

        let urls = (0...3_000).map { URL(string: "http://test.com/\($0)")! }
        measure {
            let expectation = self.expectation(description: "Image loaded")
            var finished: Int = 0
            for url in urls {
                var request = ImageRequest(url: url)
                request.processors = [] // Remove processing time from equation

                pipeline.loadImage(with: url) { _ in
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

class ImageProcessingPerformanceTests: XCTestCase {
    func testCreatingProcessorIdentifiers() {
        let decompressor = ImageProcessor.Resize(size: CGSize(width: 1, height: 1), contentMode: .aspectFill, upscale: false)

        measure {
            for _ in 0..<25_000 {
                _ = decompressor.identifier
            }
        }
    }

    func testComparingTwoProcessorCompositions() {

        let lhs = ImageProcessor.Composition([MockImageProcessor(id: "123"), ImageProcessor.Resize(size: CGSize(width: 1, height: 1), contentMode: .aspectFill, upscale: false)])
        let rhs = ImageProcessor.Composition([MockImageProcessor(id: "124"), ImageProcessor.Resize(size: CGSize(width: 1, height: 1), contentMode: .aspectFill, upscale: false)])

        measure {
            for _ in 0..<25_000 {
                if lhs.hashableIdentifier == rhs.hashableIdentifier {
                    // do nothing
                }
            }
        }
    }
}

class DataCachePeformanceTests: XCTestCase {
    var cache: DataCache!

    override func setUp() {
        cache = try! DataCache(name: UUID().uuidString)
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

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke

@Suite(.serialized)
@MainActor
struct ImagePipelinePerformanceTests {
    @Test
    func asyncAwaitPerformance() async {
        let pipeline = makePipeline()
        let requests = (0..<5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }
        await measure {
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    group.addTask {
                        _ = try? await pipeline.image(for: request)
                    }
                }
            }
        }
    }

    @Test
    func asyncAwaitPerformanceWithDiagnostics() async {
        let pipeline = makePipeline { $0.isDiagnosticsEnabled = true }
        let requests = (0..<5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }
        await measure {
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    group.addTask {
                        _ = try? await pipeline.image(for: request)
                    }
                }
            }
        }
    }

    @Test
    func memoryHitPerformance() async {
        let pipeline = makePipeline { $0.imageCache = ImageCache() }
        let requests = (0..<5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }
        let container = Test.container
        for request in requests {
            pipeline.cache[request] = container
        }
        await measure {
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    group.addTask {
                        _ = try? await pipeline.image(for: request)
                    }
                }
            }
        }
    }

    @Test
    func memoryHitPerformanceWithProcessor() async {
        let imageCache = ImageCache()
        let pipeline = makePipeline { $0.imageCache = imageCache }
        let resize = ImageProcessors.Resize(width: 320)
        let requests = (0..<5000).map {
            ImageRequest(url: URL(string: "http://test.com/\($0)"), processors: [resize])
        }
        // Small enough for every entry to stay in the cache. The cache charges
        // `Test.container` 1.2 MB, and 5000 of those evict each other, which
        // times the load path instead of the hit.
        let container = ImageContainer(image: Test.rgbImage(width: 8, height: 8))
        for request in requests {
            pipeline.cache[request] = container
        }
        #expect(imageCache.totalCount == requests.count)
        await measure {
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    group.addTask {
                        _ = try? await pipeline.image(for: request)
                    }
                }
            }
        }
        #expect(imageCache.totalCount == requests.count)
    }

    @Test
    func memoryHitPerformanceWithDiagnostics() async {
        let pipeline = makePipeline {
            $0.imageCache = ImageCache()
            $0.isDiagnosticsEnabled = true
        }
        let requests = (0..<5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }
        let container = Test.container
        for request in requests {
            pipeline.cache[request] = container
        }
        await measure {
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    group.addTask {
                        _ = try? await pipeline.image(for: request)
                    }
                }
            }
        }
    }

    @Test
    func asyncImageTaskPerformance() async {
        let pipeline = makePipeline()
        let requests = (0..<5000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")) }
        await measure {
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    group.addTask {
                        _ = try? await pipeline.imageTask(with: request).image
                    }
                }
            }
        }
    }

    /// Up to a hundred image tasks coalesced onto each download, with a data
    /// cache configured: every completed download asks the tasks waiting on it
    /// whether to store the data.
    @Test
    func coalescedLoadsWithDataCachePerformance() async {
        let pipeline = makePipeline { $0.dataCache = DataCacheMiss() }
        let requests = (0..<5000).map { ImageRequest(url: URL(string: "http://test.com/\($0 % 50)")) }
        await measure {
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    group.addTask {
                        _ = try? await pipeline.image(for: request)
                    }
                }
            }
        }
    }
}

/// Never has the data, so every iteration downloads it again.
private struct DataCacheMiss: DataCaching {
    func cachedData(for key: String) -> Data? { nil }
    func containsData(for key: String) -> Bool { false }
    func storeData(_ data: Data, for key: String) {}
    func removeData(for key: String) {}
    func removeAll() {}
}

private func makePipeline(_ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
    struct MockDecoder: ImageDecoding {
        static let container = ImageContainer(image: Test.image)

        func decode(_ data: Data) throws -> ImageContainer {
            MockDecoder.container
        }
    }

    let pipeline = ImagePipeline {
        $0.imageCache = nil

        $0.dataLoader = MockDataLoader()

        $0.isDecompressionEnabled = false

        // This must be off for this test, because rate limiter is optimized for
        // the actual loading in the apps and not the synthetic tests like this.
        $0.isRateLimiterEnabled = false

        // Remove decoding from the equation
        $0.makeImageDecoder = { _ in ImageDecoders.Empty() }

        configure(&$0)
    }

    return pipeline
}

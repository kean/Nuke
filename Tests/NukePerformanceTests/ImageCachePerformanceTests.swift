// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke

@Suite(.serialized)
@MainActor
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

    // MARK: - Eviction

    @Test
    func cacheEvictionByCount() {
        let cache = ImageCache()
        cache.countLimit = 1_000
        let image = ImageContainer(image: PlatformImage())
        let requests = (0..<100_000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")!) }

        measure {
            for request in requests {
                cache[request] = image
            }
        }
    }

    @Test
    func cacheEvictionByCost() {
        let cache = ImageCache()
        cache.costLimit = 1_000_000
        // Each entry's cost is `1 + data.count`. With entryCostLimit = 0.1
        // (default), max accepted cost is 100_000, so 10_001-byte entries
        // accumulate ~100 deep before each subsequent set evicts.
        let image = ImageContainer(image: PlatformImage(), data: Data(count: 10_000))
        let requests = (0..<100_000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")!) }

        measure {
            for request in requests {
                cache[request] = image
            }
        }
    }

    @Test
    func cacheOversizedEntryRejection() {
        let cache = ImageCache()
        cache.costLimit = 1_000 // entryCostLimit default 0.1 -> 100-byte threshold
        let oversized = ImageContainer(image: PlatformImage(), data: Data(count: 200))
        let requests = (0..<100_000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")!) }

        measure {
            for request in requests {
                cache[request] = oversized
            }
        }
    }

    // MARK: - Realistic workloads

    @Test
    func cacheMixedReadWrite() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())
        for index in 0..<2_000 {
            cache[ImageRequest(url: URL(string: "http://test.com/\(index)")!)] = image
        }

        enum Op { case read(ImageRequest); case write(ImageRequest) }
        let ops: [Op] = (0..<100_000).map { _ in
            let request = ImageRequest(url: URL(string: "http://test.com/\(Int.random(in: 0..<2_000))")!)
            return Int.random(in: 0..<10) < 8 ? .read(request) : .write(request)
        }

        measure {
            for op in ops {
                switch op {
                case .read(let request): _ = cache[request]
                case .write(let request): cache[request] = image
                }
            }
        }
    }

    @Test
    func cacheConcurrentReads() async {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())
        for index in 0..<2_000 {
            cache[ImageRequest(url: URL(string: "http://test.com/\(index)")!)] = image
        }

        let chunks: [[ImageRequest]] = (0..<8).map { _ in
            (0..<12_500).map { _ in
                ImageRequest(url: URL(string: "http://test.com/\(Int.random(in: 0..<2_000))")!)
            }
        }

        await measure {
            await withTaskGroup(of: Void.self) { group in
                for chunk in chunks {
                    group.addTask {
                        for request in chunk {
                            _ = cache[request]
                        }
                    }
                }
            }
        }
    }

    @Test
    func cacheConcurrentMixed() async {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())
        for index in 0..<2_000 {
            cache[ImageRequest(url: URL(string: "http://test.com/\(index)")!)] = image
        }

        let readChunks: [[ImageRequest]] = (0..<7).map { _ in
            (0..<12_500).map { _ in
                ImageRequest(url: URL(string: "http://test.com/\(Int.random(in: 0..<2_000))")!)
            }
        }
        let writeChunk: [ImageRequest] = (0..<12_500).map { _ in
            ImageRequest(url: URL(string: "http://test.com/\(Int.random(in: 0..<2_000))")!)
        }

        await measure {
            await withTaskGroup(of: Void.self) { group in
                for chunk in readChunks {
                    group.addTask {
                        for request in chunk {
                            _ = cache[request]
                        }
                    }
                }
                group.addTask {
                    for request in writeChunk {
                        cache[request] = image
                    }
                }
            }
        }
    }

    // MARK: - Removal & trimming

    @Test
    func cacheRemove() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())
        let requests = (0..<100_000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")!) }

        // Each iteration: populate then remove. Reported time mixes both;
        // subtract `cacheWrite` numbers to isolate the removal cost.
        measure {
            for request in requests { cache[request] = image }
            for request in requests { cache[request] = nil }
        }
    }

    @Test
    func cacheTrim() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())
        let requests = (0..<10_000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")!) }

        // Each iteration: populate then trim everything via the LRU walk.
        measure {
            for request in requests { cache[request] = image }
            cache.trim(toCount: 0)
        }
    }

    @Test
    func cacheTTLExpiration() {
        let cache = ImageCache()
        cache.ttl = 0 // every set produces an immediately-expired entry
        let image = ImageContainer(image: PlatformImage())

        let writeRequests = (0..<2_000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")!) }
        let readRequests = (0..<100_000).map { _ in
            ImageRequest(url: URL(string: "http://test.com/\(Int.random(in: 0..<2_000))")!)
        }

        // Populate (TTL=0) then read: first hit per key takes the
        // `isExpired -> _remove` branch; subsequent reads miss outright.
        measure {
            for request in writeRequests { cache[request] = image }
            for request in readRequests { _ = cache[request] }
        }
    }

    // MARK: - Cache key in isolation

    @Test
    func imageCacheKeyConstruction() {
        let requests = (0..<100_000).map { ImageRequest(url: URL(string: "http://test.com/\($0)")!) }

        measure {
            var sink = 0
            for request in requests {
                sink &+= ImageCacheKey(request: request).hashValue
            }
            return sink
        }
    }

    @Test
    func imageCacheKeyHashing() {
        let key = ImageCacheKey(request: Test.request)

        measure {
            var sink = 0
            for _ in 0..<1_000_000 {
                var hasher = Hasher()
                key.hash(into: &hasher)
                sink &+= hasher.finalize()
            }
            return sink
        }
    }

    @Test
    func imageCacheKeyEquality() {
        let urls = (0..<100).map { URL(string: "http://test.com/\($0)")! }
        let lhs = urls.map { ImageCacheKey(request: ImageRequest(url: $0)) }
        let rhs = urls.map { ImageCacheKey(request: ImageRequest(url: $0)) }

        measure {
            var matches = 0
            for _ in 0..<10_000 {
                for index in 0..<urls.count where lhs[index] == rhs[index] {
                    matches += 1
                }
            }
            return matches
        }
    }

    // MARK: - Different key shapes

    @Test
    func cacheHitWithProcessors() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())
        let processors: [any ImageProcessing] = [
            ImageProcessors.Resize(size: CGSize(width: 100, height: 100))
        ]

        for index in 0..<2_000 {
            cache[ImageRequest(url: URL(string: "http://test.com/\(index)")!, processors: processors)] = image
        }

        let requests = (0..<100_000).map { _ in
            ImageRequest(url: URL(string: "http://test.com/\(Int.random(in: 0..<2_000))")!, processors: processors)
        }

        measure {
            var hits = 0
            for request in requests where cache[request] != nil {
                hits += 1
            }
            return hits
        }
    }

    @Test
    func cacheHitWithThumbnail() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())
        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 256)

        func makeRequest(_ index: Int) -> ImageRequest {
            var request = ImageRequest(url: URL(string: "http://test.com/\(index)")!)
            request.thumbnail = thumbnail
            return request
        }

        for index in 0..<2_000 { cache[makeRequest(index)] = image }
        let requests = (0..<100_000).map { _ in makeRequest(Int.random(in: 0..<2_000)) }

        measure {
            var hits = 0
            for request in requests where cache[request] != nil {
                hits += 1
            }
            return hits
        }
    }

    @Test
    func cacheHitCustomStringKey() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())

        for index in 0..<2_000 {
            cache[ImageCacheKey(key: "id-\(index)")] = image
        }

        let keys = (0..<100_000).map { _ in ImageCacheKey(key: "id-\(Int.random(in: 0..<2_000))") }

        measure {
            var hits = 0
            for key in keys where cache[key] != nil {
                hits += 1
            }
            return hits
        }
    }

    @Test
    func cacheHitURLRequest() {
        let cache = ImageCache()
        let image = ImageContainer(image: PlatformImage())

        for index in 0..<2_000 {
            let urlRequest = URLRequest(url: URL(string: "http://test.com/\(index)")!)
            cache[ImageRequest(urlRequest: urlRequest)] = image
        }

        let requests = (0..<100_000).map { _ -> ImageRequest in
            let urlRequest = URLRequest(url: URL(string: "http://test.com/\(Int.random(in: 0..<2_000))")!)
            return ImageRequest(urlRequest: urlRequest)
        }

        measure {
            var hits = 0
            for request in requests where cache[request] != nil {
                hits += 1
            }
            return hits
        }
    }
}

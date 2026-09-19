// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: the default disk cache key is a plain concatenation of the
// image ID, the thumbnail identifier, and the processor identifiers with no
// separators, so different requests collide on disk while their memory cache
// keys (which compare the fields separately) are different.
//
// Expected: two requests with different memory cache keys don't share a disk
// cache entry – otherwise the disk cache returns an image produced by a
// different request.
//
// Actual: `makeDataCacheKey` (Sources/Nuke/Pipeline/ImagePipeline+Cache.swift:236)
// returns "http://test.com/example.jpegblurred" for both processors
// ["blur", "red"] and ["blurred"] (`ImageProcessors.Composition.identifier`
// also joins with ""), and for the URL ".../example.jpeg" + processor "1" vs
// the URL ".../example.jpeg1". After the first request stores its processed
// image (`.automatic`), the second one is served that image from the disk and
// its own processor never runs.
@Suite(.timeLimit(.minutes(5)))
struct BugDiskCacheKeyCollisionTests {
    @Test func differentProcessorsHaveDifferentDiskKeys() {
        // GIVEN
        let pipeline = ImagePipeline { $0.imageCache = nil }
        let lhs = ImageRequest(url: Test.url, processors: [
            ImageProcessors.Anonymous(id: "blur") { $0 },
            ImageProcessors.Anonymous(id: "red") { $0 }
        ])
        let rhs = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "blurred") { $0 }])

        // THEN
        #expect(pipeline.cache.makeImageCacheKey(for: lhs) != pipeline.cache.makeImageCacheKey(for: rhs))
        #expect(pipeline.cache.makeDataCacheKey(for: lhs) != pipeline.cache.makeDataCacheKey(for: rhs)) // actual: equal
    }

    @Test func urlAndProcessorDoNotBlend() {
        // GIVEN
        let pipeline = ImagePipeline { $0.imageCache = nil }
        let lhs = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1") { $0 }])
        let rhs = ImageRequest(url: URL(string: Test.url.absoluteString + "1"))

        // THEN
        #expect(pipeline.cache.makeDataCacheKey(for: lhs) != pipeline.cache.makeDataCacheKey(for: rhs)) // actual: equal
    }

    @Test func requestIsNotServedAnotherRequestsImageFromDisk() async throws {
        // GIVEN a processed image stored on disk for one request
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
        }
        let blurRed = ImageRequest(url: Test.url, processors: [
            ImageProcessors.Anonymous(id: "blur") { $0 },
            ImageProcessors.Anonymous(id: "red") { $0 }
        ])
        _ = try await pipeline.image(for: blurRed)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // WHEN a request with a different processor is loaded
        let calls = Ref(0)
        let lock = NSLock()
        let blurred = ImageRequest(url: Test.url, processors: [
            ImageProcessors.Anonymous(id: "blurred") { image in
                lock.withLock { calls.value += 1 }
                return image
            }
        ])
        let response = try await pipeline.imageTask(with: blurred).response

        // THEN its own processor runs (actual: served from disk, never runs)
        #expect(response.cacheType != .disk)
        #expect(lock.withLock { calls.value } == 1)
    }
}

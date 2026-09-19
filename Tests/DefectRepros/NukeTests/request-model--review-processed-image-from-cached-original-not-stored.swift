// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: a processed image (or a thumbnail) made from original data
// that was read from the disk cache is never stored in the disk cache, even
// with the policies that store processed images.
//
// Docs (Sources/Nuke/Pipeline/ImagePipeline+Configuration.swift):
// `.automatic` – "Store _only_ processed images for requests with
// processors"; `.storeAll` – "Stores both processed images and the original
// image data."
//
// Expected: after loading `[p1]` (or a thumbnail) for a URL whose original
// data is already in the disk cache, the processed image is in the disk
// cache under its own key, as it is when the original comes from the network.
// Actual: `TaskLoadImage.shouldStoreResponseInDataCache`
// (Sources/Nuke/Tasks/TaskLoadImage.swift:201) skips every response with
// `cacheType == .disk`. The guard is meant for data the task itself read from
// the disk cache, but the `cacheType` of the dependency's response is carried
// through `process(...)` (which replaces only `response.container`), and the
// thumbnail path in `start()` decodes the *original* data with
// `cacheType: .disk`. So the processed image is recomputed from the original
// data on every load that misses the memory cache (every app launch), which is
// the work the processed-image disk cache exists to save. The response also
// reports `cacheType == .disk` for an image that wasn't in the disk cache.
@Suite(.timeLimit(.minutes(1)))
struct RequestModelReviewProcessedFromCachedOriginalTests {
    enum Kind: String, CaseIterable, Sendable {
        case processor, thumbnail
    }

    @Test(arguments: [ImagePipeline.DataCachePolicy.automatic, .storeAll], Kind.allCases)
    func processedImageIsStoredWhenOriginalComesFromDiskCache(policy: ImagePipeline.DataCachePolicy, kind: Kind) async throws {
        // Given the original data in the disk cache
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.dataCachePolicy = policy
        }
        dataCache.store[Test.url.absoluteString] = Test.data
        let request = switch kind {
        case .processor: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
        case .thumbnail: ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 100) }
        }

        // When
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // Then the processed image is stored under its own key
        #expect(dataLoader.createdTaskCount == 0)
        #expect(dataCache.store[pipeline.cache.makeDataCacheKey(for: request)] != nil)
    }
}

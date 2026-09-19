// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: when a processed image (or a thumbnail) is produced from the
// original data found in the disk cache, it is never stored in the disk cache,
// even with the policies that store processed images (`.automatic`,
// `.storeAll`, `.storeEncodedImages`).
//
// Expected: `.automatic` – "Store _only_ processed images for requests with
// processors"; `.storeAll` – "Stores both processed images and the original
// image data". The processed image should be encoded and stored under its own
// key, the same way it is when the original comes from the network or from
// the *memory* cache (`ImagePipelineDataCachePolicyTests.policyAutomaticGivenOriginalImageInMemoryCache`).
//
// Actual: nothing is stored, so every cold load re-decodes the full original
// and re-runs the processors. `TaskLoadImage.shouldStoreResponseInDataCache`
// (Sources/Nuke/Tasks/TaskLoadImage.swift:190) skips responses with
// `cacheType == .disk`, meant for images decoded from the entry being stored,
// but the processed response inherits `cacheType == .disk` from the original
// it was made from (`process` copies the response and only replaces the
// container), and so does a thumbnail decoded from the original data.
//
// A typical sequence: a list loads `url` (stores the original), then a detail
// screen loads `url` resized – the resized image never reaches the disk.
@Suite(.timeLimit(.minutes(5)))
struct BugProcessedImageFromDiskOriginalTests {
    @Test(arguments: [ImagePipeline.DataCachePolicy.automatic, .storeAll, .storeEncodedImages])
    func processedImageIsStored(policy: ImagePipeline.DataCachePolicy) async throws {
        // GIVEN only the original data in the disk cache
        let dataCache = MockDataCache()
        dataCache.store[Test.url.absoluteString] = Test.data
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
            $0.dataCache = dataCache
            $0.dataCachePolicy = policy
            $0.makeImageEncoder = { _ in MockImageEncoder(result: Test.data) }
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN (actual: only the original key is in the store)
        #expect(response.image.nk_test_processorIDs == ["p1"])
        #expect(dataCache.store[Test.url.absoluteString + "p1"] != nil, "Stored keys: \(dataCache.store.keys.sorted())")
    }

    @Test func thumbnailIsStored() async throws {
        // GIVEN only the original data in the disk cache
        let dataCache = MockDataCache()
        dataCache.store[Test.url.absoluteString] = Test.data
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeAll
        }
        let request = ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 100) }

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN (actual: false)
        #expect(pipeline.cache.containsData(for: request), "Stored keys: \(dataCache.store.keys.sorted())")
    }
}

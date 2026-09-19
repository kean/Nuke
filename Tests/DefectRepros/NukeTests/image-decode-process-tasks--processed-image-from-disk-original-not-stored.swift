// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: a processed image made from an image in the disk cache is never stored
// in the disk cache, while the same image made from the memory cache or from
// the network is.
//
// Expected: with `.automatic` ("Store _only_ processed images for requests with
// processors") or `.storeAll`, the processed image is encoded and stored under
// the processed request's key whenever it isn't there yet – which is exactly
// the case when the pipeline had to build it from the original data.
//
// Actual: `TaskLoadImage.process` copies the input response, including its
// `cacheType`, into the processed response. When the original came from the
// disk cache, the processed response has `cacheType == .disk`, and
// `shouldStoreResponseInDataCache(_:)` skips every response with that cache
// type – a check meant for the image read from the processed request's own
// disk entry. So the processed image is recomputed from the original data on
// every cold start, forever. Built from an original in the *memory* cache
// (`cacheType == .memory`) the same image is stored, see
// `ImagePipelineLoadImageTaskTests.processedImageMadeFromMemoryCachedOriginalIsStoredOnDisk`.
//
// Sources/Nuke/Tasks/TaskLoadImage.swift:208 (with the `var response = response` at :86)
@Suite(.timeLimit(.minutes(5)))
struct ProcessedImageFromDiskOriginalBugRepro {
    @Test(arguments: [ImagePipeline.DataCachePolicy.automatic, .storeAll])
    func processedImageMadeFromDiskCachedOriginalIsStoredOnDisk(policy: ImagePipeline.DataCachePolicy) async throws {
        // GIVEN only the original image data in the disk cache
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.dataCachePolicy = policy
        }
        dataCache.store[Test.url.absoluteString] = Test.data
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN the processed image is stored for the next time
        #expect(response.image.nk_test_processorIDs == ["1"])
        #expect(dataLoader.createdTaskCount == 0)
        #expect(dataCache.store[pipeline.cache.makeDataCacheKey(for: request)] != nil) // Actual: nil
    }
}

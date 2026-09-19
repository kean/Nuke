// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: `.returnCacheDataDontLoad` fails for any request with
// processors unless the exact *processed* image is cached, even when the
// original image (in memory or on disk) or an intermediate result is cached
// and the pipeline could produce the image without loading anything.
//
// Expected: "Use existing cache data and fail if no cached data is available."
// With the default `.storeOriginalData` policy only the original data is ever
// on disk, so a processed request is expected to be served from it – the way
// it is without the option (`ImagePipelineCacheLayerPriorityTests.givenOriginalImageInDiskCache`),
// and the way a thumbnail request with `.returnCacheDataDontLoad` already is
// (TaskLoadImage.start() falls back to the original data for thumbnails).
//
// Actual: `ImagePipeline.Error.dataMissingInCache`. `TaskLoadImage.fetchImage()`
// (Sources/Nuke/Tasks/TaskLoadImage.swift:51) fails on the option *before*
// creating the dependency `TaskLoadImage` for the request with one processor
// fewer, which is what looks up the intermediate/original images in the
// caches. Before 3e9d0bd2 "Rework task reuse in TaskLoadImage" the pipeline
// at least checked the memory cache for intermediate images before failing;
// that part is a regression, the disk part never worked.
@Suite(.timeLimit(.minutes(5)))
struct BugReturnCacheDataDontLoadProcessedRequestTests {
    private let dataLoader = MockDataLoader()
    private let imageCache = MockImageCache()
    private let dataCache = MockDataCache()

    private var pipeline: ImagePipeline {
        ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
    }

    @Test func processedImageIsProducedFromTheOriginalDataOnDisk() async throws {
        // GIVEN only the original data in the disk cache (the default policy)
        dataCache.store[Test.url.absoluteString] = Test.data
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], options: [.returnCacheDataDontLoad])

        // WHEN/THEN (actual: throws `dataMissingInCache`)
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.image.nk_test_processorIDs == ["1"])
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func processedImageIsProducedFromTheOriginalImageInMemory() async throws {
        // GIVEN
        let pipeline = self.pipeline
        pipeline.cache[Test.request] = Test.container
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], options: [.returnCacheDataDontLoad])

        // WHEN/THEN (actual: throws `dataMissingInCache`)
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.image.nk_test_processorIDs == ["1"])
    }

    @Test func processedImageIsProducedFromTheIntermediateImageInMemory() async throws {
        // GIVEN
        let pipeline = self.pipeline
        pipeline.cache[ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])] = Test.container
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1"), MockImageProcessor(id: "2")], options: [.returnCacheDataDontLoad])

        // WHEN/THEN (actual: throws `dataMissingInCache`)
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.image.nk_test_processorIDs == ["2"])
    }
}

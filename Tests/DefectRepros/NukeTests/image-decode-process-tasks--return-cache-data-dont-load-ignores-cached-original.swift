// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: `.returnCacheDataDontLoad` fails a request with processors with
// `.dataMissingInCache` even though the image it is made from is cached.
//
// Expected: "Use existing cache data and fail if no cached data is available."
// Without the option, the pipeline builds a processed image from the cached
// original (memory or disk) or from a cached intermediate image, without
// touching the network. With the option, it should do the same – the data it
// needs *is* in the cache. This matters most with the default
// `dataCachePolicy` (`.storeOriginalData`), where processed images are never
// written to disk: after a relaunch, a processed request with
// `.returnCacheDataDontLoad` can never succeed, even though the original data
// is on disk. Thumbnails already get this right – `TaskLoadImage.start()`
// looks up the original data for a thumbnail request before giving up.
//
// Actual: `TaskLoadImage.fetchImage()` checks `.returnCacheDataDontLoad`
// *before* it subscribes to the `TaskLoadImage` for the request without the
// last processor, so the lookups of the intermediate and original images never
// happen, and the request fails with `.dataMissingInCache`. The check moved
// here from the data-loading task in 4f2ce69f ("Add TaskLoadData"); before that
// it was only applied when the data had to be downloaded.
//
// Sources/Nuke/Tasks/TaskLoadImage.swift:52
@Suite(.timeLimit(.minutes(5)))
struct ReturnCacheDataDontLoadWithProcessorsBugRepro {
    @Test func processedImageIsMadeFromOriginalDataInDiskCache() async throws {
        // GIVEN only the original image data in the disk cache
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
        dataCache.store[Test.url.absoluteString] = Test.data
        let request = ImageRequest(
            url: Test.url,
            processors: [MockImageProcessor(id: "1")],
            options: [.returnCacheDataDontLoad]
        )

        // WHEN
        let response = try await pipeline.imageTask(with: request).response // Actual: throws .dataMissingInCache

        // THEN
        #expect(response.image.nk_test_processorIDs == ["1"])
        #expect(response.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func processedImageIsMadeFromOriginalImageInMemoryCache() async throws {
        // GIVEN only the original image in the memory cache
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }
        imageCache[Test.request] = Test.container
        let request = ImageRequest(
            url: Test.url,
            processors: [MockImageProcessor(id: "1")],
            options: [.returnCacheDataDontLoad]
        )

        // WHEN
        let response = try await pipeline.imageTask(with: request).response // Actual: throws .dataMissingInCache

        // THEN
        #expect(response.image.nk_test_processorIDs == ["1"])
        #expect(response.cacheType == .memory)
        #expect(dataLoader.createdTaskCount == 0)
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: `data(for:)` (and `ImagePrefetcher` with the `.diskCache` destination,
// which uses the same data tasks) never reads back the original data it
// stores when the request has a thumbnail or processors, so every call
// downloads the image again even though the disk cache has it.
//
// Sources/Nuke/Tasks/TaskLoadData.swift `start()` looks the data up with the
// full request key: "<url><thumbnail id>" or "<url><processor ids>". On a
// miss, it fetches the *original* data (`request.withProcessors([])`), which
// `storeDataInCacheIfNeeded` (TaskFetchOriginalData.swift) stores under the
// sanitized key "<url>" (no processors, no thumbnail). The next identical
// request looks up the full key again, misses, and goes to the network.
//
// `TaskLoadImage.start()` handles exactly this for thumbnails with a second
// lookup (`lookUpCachedData(for: request.withoutThumbnail())`); `TaskLoadData`
// has no such fallback. `TaskFetchOriginalData` never reads the disk cache.
//
// Expected: the second identical `data(for:)` call is served from the disk
//           cache the first call populated (1 download).
// Actual:   2 downloads, for both a thumbnail request and (with the default
//           `.storeOriginalData` policy) a request with a processor.

@Suite(.timeLimit(.minutes(5)))
struct DataTaskNeverReadsBackOriginalDataBugTests {
    @Test func thumbnailDataRequestIsServedFromTheDiskCacheTheSecondTime() async throws {
        // GIVEN
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 100)

        // WHEN the same data is requested twice
        _ = try await pipeline.data(for: request)
        #expect(dataCache.store[Test.url.absoluteString] == Test.data) // stored by the first call
        let (data, _) = try await pipeline.data(for: request)

        // THEN
        #expect(data == Test.data)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func processedDataRequestIsServedFromTheDiskCacheTheSecondTime() async throws {
        // GIVEN the default `.storeOriginalData` policy
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Resize(width: 100)])

        // WHEN the same data is requested twice
        _ = try await pipeline.data(for: request)
        #expect(dataCache.store[Test.url.absoluteString] == Test.data) // stored by the first call
        _ = try await pipeline.data(for: request)

        // THEN
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func prefetchingThumbnailsToDiskIsServedFromTheDiskCacheTheSecondTime() async throws {
        // GIVEN
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
        var request = Test.request
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 100)

        // WHEN the thumbnail is prefetched to disk twice (the way the
        // prefetcher does it: a data task)
        _ = try await pipeline.makeStartedImageTask(with: request, isDataTask: true, isPrefetch: true).response
        _ = try await pipeline.makeStartedImageTask(with: request, isDataTask: true, isPrefetch: true).response

        // THEN
        #expect(dataLoader.createdTaskCount == 1)
    }
}

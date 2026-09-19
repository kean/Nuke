// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: when a thumbnail request finds data under its own disk cache key that
// can't be used (it fails to decode, or the decoder factory declines it), the
// pipeline skips the original image data in the disk cache and downloads the
// image again – or, with `.returnCacheDataDontLoad`, fails with
// `.dataMissingInCache`.
//
// Expected: an unusable cache entry is treated as a miss – that's what
// `TaskLoadImage.didFinishDecoding(with: nil)` does ("load as if there was no
// data in the cache"). For a thumbnail request without processors, a miss for
// the thumbnail key falls back to the original data
// (`lookUpCachedData(for: request.withoutThumbnail())` in `start()`), which
// generates the thumbnail locally.
//
// Actual: `start()` picks one branch up front. When the thumbnail key has data,
// `decodeCachedData` runs, and on failure `didFinishDecoding(with: nil)` calls
// `fetchImage()` directly, bypassing the original-data branch. The original
// data is on disk the whole time.
//
// Sources/Nuke/Tasks/TaskLoadImage.swift:21-28 and :45
@Suite(.timeLimit(.minutes(5)))
struct UnusableThumbnailEntryBugRepro {
    @Test func thumbnailIsMadeFromOriginalDataWhenItsOwnEntryIsCorrupted() async throws {
        // GIVEN a corrupted thumbnail entry and the original data on disk
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
        var request = ImageRequest(url: Test.url)
        request.thumbnail = .init(maxPixelSize: 400)
        dataCache.store[pipeline.cache.makeDataCacheKey(for: request)] = Data("corrupted".utf8)
        dataCache.store[Test.url.absoluteString] = Test.data

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN the thumbnail is generated from the original data on disk
        #expect(response.image.sizeInPixels == CGSize(width: 400, height: 300))
        #expect(dataLoader.createdTaskCount == 0) // Actual: 1
    }

    @Test func thumbnailIsMadeFromOriginalDataWhenLoadingIsNotAllowed() async throws {
        // GIVEN a corrupted thumbnail entry and the original data on disk
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
        var request = ImageRequest(url: Test.url, options: [.returnCacheDataDontLoad])
        request.thumbnail = .init(maxPixelSize: 400)
        dataCache.store[pipeline.cache.makeDataCacheKey(for: request)] = Data("corrupted".utf8)
        dataCache.store[Test.url.absoluteString] = Test.data

        // WHEN
        let response = try await pipeline.imageTask(with: request).response // Actual: throws .dataMissingInCache

        // THEN
        #expect(response.image.sizeInPixels == CGSize(width: 400, height: 300))
    }
}

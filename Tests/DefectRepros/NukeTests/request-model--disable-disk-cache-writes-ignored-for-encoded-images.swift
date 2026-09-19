// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG: `ImageRequest.Options.disableDiskCacheWrites` (and so
// `.disableDiskCache`) doesn't prevent the pipeline from writing an encoded
// image to the disk cache. (Found independently of pipeline-caching--disable-
// disk-writes-ignored-for-encoded-images.swift; same root cause.)
//
// Docs (Sources/Nuke/ImageRequest.swift:319): "Disables disk cache writes
// (see `DataCaching`)."
//
// Expected: no disk cache write for a request with the option.
// Actual: `TaskFetchOriginalData.shouldStoreDataInDiskCache` checks the option
// for the original data, but `TaskLoadImage.shouldStoreResponseInDataCache`
// (Sources/Nuke/Tasks/TaskLoadImage.swift:205) never looks at
// `request.options`, so with `.automatic`/`.storeAll` (processed images and
// thumbnails) and `.storeEncodedImages` (every image) the encoded image is
// written anyway. The check was dropped in 19423094 ("TaskLoadImage no longer
// needs to check subscribed tasks"), which removed the subscriber walk that
// did it without replacing it with a check of `request.options`.
@Suite(.timeLimit(.minutes(1)))
struct RequestModelBugDisableDiskCacheWritesTests {
    @Test(arguments: [
        (ImagePipeline.DataCachePolicy.automatic, true),
        (.storeAll, true),
        (.storeEncodedImages, false)
    ])
    func noDiskWritesWithDiskCacheWritesDisabled(policy: ImagePipeline.DataCachePolicy, hasProcessor: Bool) async throws {
        // Given
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.dataCachePolicy = policy
        }
        let request = ImageRequest(
            url: Test.url,
            processors: hasProcessor ? [MockImageProcessor(id: "p1")] : [],
            options: [.disableDiskCacheWrites]
        )

        // When
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.isEmpty)
    }
}

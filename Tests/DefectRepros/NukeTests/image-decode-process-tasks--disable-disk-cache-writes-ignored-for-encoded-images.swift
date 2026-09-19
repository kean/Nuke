// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: `ImageRequest.Options.disableDiskCacheWrites` is ignored when
// `TaskLoadImage` stores an encoded (processed) image in the data cache.
//
// Expected: a request with `.disableDiskCacheWrites` never writes to the
// `DataCaching`. The option is documented as "Disables disk cache writes", and
// the pipeline honors it everywhere else: `TaskFetchOriginalData`
// (`shouldStoreDataInDiskCache()` checks it for the original data) and
// `ImagePipeline.Cache.storeCachedData(_:for:)`.
//
// Actual: with `dataCachePolicy` `.automatic`, `.storeAll`, or
// `.storeEncodedImages`, the processed image is encoded and written to the
// data cache anyway. `TaskLoadImage.shouldStoreResponseInDataCache(_:)` checks
// the policy but never `request.options`, and `storeImageInDataCache(_:)`
// writes with `dataCache.storeData` directly ("Storing directly ignoring
// `ImageRequest.Options`"). The option check was removed in 19423094
// ("TaskLoadImage no longer needs to check subscribed tasks") when the options
// became part of the task key, but no check of the task's own
// `request.options` replaced it.
//
// Sources/Nuke/Tasks/TaskLoadImage.swift:206
@Suite(.timeLimit(.minutes(5)))
struct DisableDiskCacheWritesForEncodedImagesBugRepro {
    @Test(arguments: [ImagePipeline.DataCachePolicy.automatic, .storeAll, .storeEncodedImages])
    func processedImageIsNotWrittenWhenDiskCacheWritesAreDisabled(policy: ImagePipeline.DataCachePolicy) async throws {
        // GIVEN
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.dataCachePolicy = policy
        }
        let request = ImageRequest(
            url: Test.url,
            processors: [MockImageProcessor(id: "1")],
            options: [.disableDiskCacheWrites]
        )

        // WHEN
        _ = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN nothing is written to the disk cache
        #expect(dataCache.writeCount == 0) // Actual: 1
        #expect(dataCache.store.isEmpty)   // Actual: contains "http://test.com/example.jpeg1"
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG (docs vs behavior): an image returned by an
// `ImageRequest(id:image:)` closure is encoded and stored in the disk cache.
//
// Docs (Sources/Nuke/ImageRequest.swift:252): "Unlike
// `init(id:data:processors:priority:options:)`, the image is never stored in
// the disk cache because no raw data is available."
//
// Expected: no disk cache write for an image closure request, whatever the
// data cache policy (or the doc says which policies store it).
// Actual: with `.storeEncodedImages` (and with `.automatic`/`.storeAll` once
// the request has processors) `TaskLoadImage.shouldStoreResponseInDataCache`
// (Sources/Nuke/Tasks/TaskLoadImage.swift:205) returns `true` for the
// closure's image like for any other, so it's encoded with `ImageEncoders.Default`
// and written under the request's ID. The note only holds for the default
// `.storeOriginalData` policy.
@Suite(.timeLimit(.minutes(1)))
struct RequestModelBugClosureImageDiskCacheTests {
    @Test(arguments: [
        (ImagePipeline.DataCachePolicy.storeEncodedImages, false),
        (.automatic, true),
        (.storeAll, true)
    ])
    func closureImageIsNeverStoredInDiskCache(policy: ImagePipeline.DataCachePolicy, hasProcessor: Bool) async throws {
        // Given
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.dataCachePolicy = policy
        }
        let request = ImageRequest(
            id: "closure-image",
            image: { Test.container },
            processors: hasProcessor ? [MockImageProcessor(id: "p1")] : []
        )

        // When
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.isEmpty)
    }
}

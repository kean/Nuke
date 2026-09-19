// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// SUSPECTED BUG (docs vs. behavior): `ImageRequest.init(id:image:processors:priority:options:)`
// documents "Unlike `init(id:data:...)`, the image is never stored in the disk
// cache because no raw data is available", but the pipeline encodes and stores
// the image in the disk cache whenever the data cache policy stores encoded
// images: always with `.storeEncodedImages`, and for requests with processors
// with `.automatic` and `.storeAll`.
//
// Expected (per the doc): the disk cache stays empty for an image closure
// request.
//
// Actual: the encoded image is stored under the request ID ("closure", or
// "closurep1" with a processor). `TaskLoadImage.shouldStoreResponseInDataCache`
// (Sources/Nuke/Tasks/TaskLoadImage.swift:190) doesn't distinguish the `.image`
// resource. Either the doc (Sources/Nuke/ImageRequest.swift:249) or the
// behavior needs to change.
@Suite(.timeLimit(.minutes(5)))
struct BugImageClosureRequestDiskCacheTests {
    @Test(arguments: [
        (ImagePipeline.DataCachePolicy.storeEncodedImages, false),
        (.automatic, true),
        (.storeAll, true)
    ])
    func imageClosureRequestIsNeverStoredOnDisk(policy: ImagePipeline.DataCachePolicy, hasProcessor: Bool) async throws {
        // GIVEN
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
            $0.dataCache = dataCache
            $0.dataCachePolicy = policy
        }
        let request = ImageRequest(
            id: "closure",
            image: { Test.container },
            processors: hasProcessor ? [MockImageProcessor(id: "p1")] : []
        )

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN (actual: the encoded image is stored)
        #expect(dataCache.store.isEmpty, "Stored keys: \(dataCache.store.keys.sorted())")
    }
}

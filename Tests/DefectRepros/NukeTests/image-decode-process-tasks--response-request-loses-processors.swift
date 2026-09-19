// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: `ImageResponse.request` of a freshly processed image is the request
// *without* the processors.
//
// Expected: `ImageResponse.request` is documented as "The request for which
// the response was created" – the request of the `ImageTask`, processors
// included. That's also what the response has when the processed image comes
// from the memory or the disk cache.
//
// Actual: `TaskLoadImage.process` starts from the response of the task it
// depends on – created for `request.withProcessors(request.processors.dropLast())`
// – and replaces only its `container` (`var response = response;
// response.container = ...`). The final response therefore carries the
// request of the innermost task, which has no processors: the same image
// request yields `response.request.processors.count == 1` from the cache and
// `0` from the network.
//
// Sources/Nuke/Tasks/TaskLoadImage.swift:86
@Suite(.timeLimit(.minutes(5)))
struct ProcessedResponseRequestBugRepro {
    @Test func responseOfProcessedImageHasTheRequestWithTheProcessors() async throws {
        // GIVEN
        let imageCache = MockImageCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = imageCache
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])

        // WHEN the image is loaded, then loaded again from the memory cache
        let loaded = try await pipeline.imageTask(with: request).response
        let cached = try await pipeline.imageTask(with: request).response

        // THEN both responses are for the request with the processor
        #expect(cached.cacheType == .memory)
        #expect(cached.request.processors.count == 1)
        #expect(loaded.request.processors.count == 1) // Actual: 0
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: a processed GIF is never stored in the disk cache.
//
// Expected: with `dataCachePolicy` `.automatic` ("Store _only_ processed
// images for requests with processors"), `.storeAll`, or
// `.storeEncodedImages`, the processed image is encoded and stored under the
// key of the processed request – as it is for JPEG, PNG, HEIC, and every
// other format.
//
// Actual: nothing is stored. Processing keeps `ImageContainer.type` (`.gif`)
// but drops `ImageContainer.data` (`ImageContainer.map`, since #958), and the
// default `ImageEncoding.encode(_:context:)` – which `ImageEncoders.Default`
// doesn't override – returns `container.data` for any container of type
// `.gif`: `nil` here. `TaskLoadImage.storeImageInDataCache(_:)` then stores
// nothing. With `.automatic`, the original data isn't stored either (the
// request has processors), so a processed GIF is downloaded again on every
// cold start.
//
// Sources/Nuke/Encoding/ImageEncoding.swift:28 (with ImageContainer.swift:108)
@Suite(.timeLimit(.minutes(5)))
struct ProcessedGIFDiskCacheBugRepro {
    @Test(arguments: [ImagePipeline.DataCachePolicy.automatic, .storeAll, .storeEncodedImages])
    func processedGIFIsStoredInDiskCache(policy: ImagePipeline.DataCachePolicy) async throws {
        // GIVEN a GIF and a request that processes it
        let dataLoader = MockDataLoader()
        dataLoader.results[Test.url] = .success(
            (Test.animatedGIF(frameCount: 3), URLResponse(url: Test.url, mimeType: "gif", expectedContentLength: 0, textEncodingName: nil))
        )
        let dataCache = MockDataCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.dataCachePolicy = policy
        }
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN the processed image is stored
        #expect(response.container.type == .gif)
        #expect(response.container.data == nil)
        let key = pipeline.cache.makeDataCacheKey(for: request)
        #expect(dataCache.store[key] != nil) // Actual: nil
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImagePipelineDelegateTests {
    private let dataLoader: MockDataLoader
    private let dataCache: MockDataCache
    private let pipeline: ImagePipeline
    private let delegate: MockImagePipelineDelegate

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let delegate = MockImagePipelineDelegate()
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.delegate = delegate
        self.pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
            $0.imageCache = nil
            $0.debugIsSyncImageEncoding = true
        }
    }

    @Test @MainActor func customizingDataCacheKey() async throws {
        // GIVEN
        let imageURLSmall = URL(string: "https://example.com/image-01-small.jpeg")!
        let imageURLMedium = URL(string: "https://example.com/image-01-medium.jpeg")!

        dataLoader.results[imageURLMedium] = .success(
            (Test.data, URLResponse(url: imageURLMedium, mimeType: "jpeg", expectedContentLength: Test.data.count, textEncodingName: nil))
        )

        // GIVEN image is loaded from medium size URL and saved in cache using imageId "image-01-small"
        let requestA = ImageRequest(
            url: imageURLMedium,
            processors: [.resize(width: 44)],
            userInfo: ["imageId": "image-01-small"]
        )
        _ = try await pipeline.image(for: requestA)

        let data = try #require(dataCache.cachedData(for: "image-01-small"))
        let image = try #require(PlatformImage(data: data))
        #expect(image.sizeInPixels.width == 44 * Screen.scale)

        // GIVEN a request for a small image
        let requestB = ImageRequest(
            url: imageURLSmall,
            userInfo: ["imageId": "image-01-small"]
        )

        // WHEN/THEN the image is returned from the disk cache
        let responseB = try await pipeline.imageTask(with: requestB).response
        #expect(responseB.image.sizeInPixels.width == 44 * Screen.scale)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func dataIsStoredInCache() async throws {
        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(!dataCache.store.isEmpty)
    }

    @Test func dataIsStoredInCacheWhenCacheDisabled() async throws {
        // WHEN
        delegate.isCacheEnabled = false
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(dataCache.store.isEmpty)
    }
}

private final class MockImagePipelineDelegate: ImagePipelineDelegate, @unchecked Sendable {
    var isCacheEnabled = true

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        request.userInfo["imageId"] as? String
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void) {
        completion(isCacheEnabled ? data : nil)
    }
}

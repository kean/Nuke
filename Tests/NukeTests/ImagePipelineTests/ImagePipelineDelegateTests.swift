// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@Suite class ImagePipelineDelegateTests {
    private var dataLoader: MockDataLoader!
    private var dataCache: MockDataCache!
    private var pipeline: ImagePipeline!
    private var delegate: MockImagePipelineDelegate!

    init() {
        dataLoader = MockDataLoader()
        dataCache = MockDataCache()
        delegate = MockImagePipelineDelegate()

        pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
            $0.imageCache = nil
            $0.debugIsSyncImageEncoding = true
        }
    }


    @MainActor
    @Test func customizingDataCacheKey() async throws {
        // Given
        let imageURLSmall = URL(string: "https://example.com/image-01-small.jpeg")!
        let imageURLMedium = URL(string: "https://example.com/image-01-medium.jpeg")!

        dataLoader.results[imageURLMedium] = .success(
            (Test.data, URLResponse(url: imageURLMedium, mimeType: "jpeg", expectedContentLength: Test.data.count, textEncodingName: nil))
        )

        // Given image is loaded from medium size URL and saved in cache using imageId "image-01-small"
        let requestA = ImageRequest(
            url: imageURLMedium,
            processors: [.resize(width: 44)],
            userInfo: ["imageId": "image-01-small"]
        )
        _ = try await pipeline.image(for: requestA)

        let data = try #require(dataCache.cachedData(for: "image-01-small"))
        let image = try #require(PlatformImage(data: data))
        #expect(image.sizeInPixels.width == 44 * Screen.scale)

        // Given a request for a small image
        let requestB = ImageRequest(
            url: imageURLSmall,
            userInfo: ["imageId": "image-01-small"]
        )

        // When
        let image2 = try await pipeline.image(for: requestB)

        // Then the image is returned from the disk cache
        #expect(image2.sizeInPixels.width == 44 * Screen.scale)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func dataIsStoredInCache() async throws {
        // When
        _ = try await pipeline.image(for: Test.request)

        // Then
            #expect(!dataCache.store.isEmpty)
    }

    @Test func dataIsStoredInCacheWhenCacheDisabled() async throws {
        // When
        delegate.isCacheEnabled = false
        _ = try await pipeline.image(for: Test.request)

        // Then
        #expect(dataCache.store.isEmpty)
    }
}

private final class MockImagePipelineDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    var isCacheEnabled = true

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        request.userInfo["imageId"] as? String
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void) {
        completion(isCacheEnabled ? data : nil)
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

/// Test how well image pipeline interacts with memory cache.
@Suite struct ImagePipelineImageCacheTests {
    var dataLoader: MockDataLoader!
    var cache: MockImageCache!
    var pipeline: ImagePipeline!

    init() {
        dataLoader = MockDataLoader()
        cache = MockImageCache()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
        }
    }

    @Test func cacheWrite() async throws {
        // When
        _ = try await pipeline.image(for: Test.request)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(cache[Test.request] != nil)
    }

    @Test func cacheRead() async throws {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        // When
        _ = try await pipeline.image(for: Test.request)

        // Then
        #expect(dataLoader.createdTaskCount == 0)
        #expect(cache[Test.request] != nil)
    }

    @Test func cacheWriteDisabled() async throws {
        // Given
        var request = Test.request
        request.options.insert(.disableMemoryCacheWrites)

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(cache[Test.request] == nil)
    }

    @Test func memoryCacheReadDisabled() async throws {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        var request = Test.request
        request.options.insert(.disableMemoryCacheReads)

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(cache[Test.request] != nil)
    }

    @Test func reloadIgnoringCachedData() async throws {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        var request = Test.request
        request.options.insert(.reloadIgnoringCachedData)

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
        #expect(cache[Test.request] != nil)
    }

    @Test func generatedThumbnailDataIsStoredIncache() async throws {
        // When
        let request = ImageRequest(
            url: Test.url,
            userInfo: [.thumbnailKey: ImageRequest.ThumbnailOptions(
                size: CGSize(width: 400, height: 400),
                unit: .pixels,
                contentMode: .aspectFit
            )]
        )

        _ = try await pipeline.image(for: request)

        // Then
        let container = try #require(pipeline.cache[request])
        #expect(container.image.sizeInPixels == CGSize(width: 400, height: 300))
        #expect(pipeline.cache[ImageRequest(url: Test.url)] == nil)
    }
}

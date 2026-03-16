// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Test how well image pipeline interacts with memory cache.
@Suite(.timeLimit(.minutes(2)))
struct ImagePipelineImageCacheTests {
    let dataLoader: MockDataLoader
    let cache: MockImageCache
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let cache = MockImageCache()
        self.dataLoader = dataLoader
        self.cache = cache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
        }
    }

    @Test func thatImageIsLoaded() async throws {
        _ = try await pipeline.image(for: Test.request)
    }

    // MARK: Caching

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

    @Test func generatedThumbnailDataIsStoredInCache() async throws {
        // When
        let request = ImageRequest(url: Test.url).with { $0.thumbnail = .init(size: CGSize(width: 400, height: 400), unit: .pixels, contentMode: .aspectFit) }
        _ = try await pipeline.image(for: request)

        // Then
        let container = try #require(pipeline.cache[request])
        #expect(container.image.sizeInPixels == CGSize(width: 400, height: 300))
        #expect(pipeline.cache[ImageRequest(url: Test.url)] == nil)
    }
}

/// Make sure that cache layers are checked in the correct order and the
/// minimum necessary number of cache lookups are performed.
@Suite(.timeLimit(.minutes(2)))
struct ImagePipelineCacheLayerPriorityTests {
    let pipeline: ImagePipeline
    let dataLoader: MockDataLoader
    let imageCache: MockImageCache
    let dataCache: MockDataCache
    let processorFactory: MockProcessorFactory

    let request: ImageRequest
    let intermediateRequest: ImageRequest
    let processedImage: ImageContainer
    let intermediateImage: ImageContainer
    let originalRequest: ImageRequest
    let originalImage: ImageContainer

    init() {
        let dataCache = MockDataCache()
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let processorFactory = MockProcessorFactory()
        self.dataCache = dataCache
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.processorFactory = processorFactory

        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = imageCache
        }

        self.request = ImageRequest(url: Test.url, processors: [
            processorFactory.make(id: "1"),
            processorFactory.make(id: "2")
        ])

        self.intermediateRequest = ImageRequest(url: Test.url, processors: [
            processorFactory.make(id: "1")
        ])

        self.originalRequest = ImageRequest(url: Test.url)

        do {
            let image = PlatformImage(data: Test.data)!
            image.nk_test_processorIDs = ["1", "2"]
            self.processedImage = ImageContainer(image: image)
        }

        do {
            let image = PlatformImage(data: Test.data)!
            image.nk_test_processorIDs = ["1"]
            self.intermediateImage = ImageContainer(image: image)
        }

        self.originalImage = ImageContainer(image: PlatformImage(data: Test.data)!)
    }

    @Test func givenProcessedImageInMemoryCache() async throws {
        // GIVEN
        imageCache[request] = processedImage

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.image === processedImage.image)
        #expect(response.cacheType == .memory)

        // THEN
        #expect(imageCache.readCount == 1)
        #expect(imageCache.writeCount == 1) // Initial write
        #expect(dataCache.readCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenProcessedImageInBothMemoryAndDiskCache() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.all])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.image === processedImage.image)
        #expect(response.cacheType == .memory)

        // THEN
        #expect(imageCache.readCount == 1)
        #expect(imageCache.writeCount == 1) // Initial write
        #expect(dataCache.readCount == 0)
        #expect(dataCache.writeCount == 1) // Initial write
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenProcessedImageInDiskCache() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.disk])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.cacheType == .disk)

        // THEN
        #expect(imageCache.readCount == 1)
        #expect(imageCache.writeCount == 1) // Initial write
        #expect(dataCache.readCount == 1)
        #expect(dataCache.writeCount == 1) // Initial write
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenProcessedImageInDiskCacheAndIntermediateImageInMemoryCache() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.disk])
        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.cacheType == .disk)

        // THEN
        #expect(imageCache.readCount == 1)
        #expect(imageCache.writeCount == 2) // Initial write
        #expect(imageCache[request] != nil)
        #expect(imageCache[intermediateRequest] != nil)
        #expect(dataCache.readCount == 1)
        #expect(dataCache.writeCount == 1) // Initial write
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenIntermediateImageInMemoryCache() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == .memory)

        // THEN
        #expect(imageCache.readCount == 2) // Processed + intermediate
        #expect(imageCache.writeCount == 2) // Initial write
        #expect(imageCache[request] != nil)
        #expect(imageCache[intermediateRequest] != nil)
        #expect(dataCache.readCount == 1) // Check original image
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenOriginalAndIntermediateImageInMemoryCache() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.memory])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == .memory)

        // THEN
        #expect(imageCache.readCount == 2) // Processed + intermediate
        #expect(imageCache.writeCount == 3) // Initial write + write processed
        #expect(imageCache[originalRequest] != nil)
        #expect(imageCache[request] != nil)
        #expect(imageCache[intermediateRequest] != nil)
        #expect(dataCache.readCount == 1) // Check original image
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenOriginalImageInBothCaches() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.all])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == .memory)

        // THEN
        #expect(imageCache.readCount == 3) // Processed + intermediate + original
        #expect(imageCache.writeCount == 2) // Processed + original
        #expect(imageCache[originalRequest] != nil)
        #expect(imageCache[request] != nil)
        #expect(dataCache.readCount == 2) // "1", "2"
        #expect(dataCache.writeCount == 1) // Initial
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenOriginalImageInDiskCache() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.disk])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == .disk)

        // THEN
        #expect(imageCache.readCount == 3) // Processed + intermediate + original
        #expect(imageCache.writeCount == 1) // Processed
        #expect(imageCache[request] != nil)
        #expect(dataCache.readCount == 3) // "1" + "2" + original
        #expect(dataCache.writeCount == 1) // Initial
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func policyStoreEncodedImagesGivenDataAlreadyStored() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
        pipeline.cache.storeCachedImage(Test.container, for: request, caches: [.disk])
        dataCache.resetCounters()
        imageCache.resetCounters()

        // WHEN
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.cacheType == .disk)

        // THEN
        #expect(imageCache.readCount == 1)
        #expect(imageCache.writeCount == 1)
        #expect(dataCache.readCount == 1)
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: ImageRequest.Options

    @Test func givenOriginalImageInDiskCacheAndDiskReadsDisabled() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.disk])

        // WHEN
        var request = request
        request.options.insert(.disableDiskCacheReads)
        let response = try await pipeline.imageTask(with: request).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == nil)

        // THEN
        #expect(imageCache.readCount == 3) // Processed + intermediate + original
        #expect(imageCache.writeCount == 1) // Processed
        #expect(imageCache[request] != nil)
        #expect(dataCache.readCount == 0) // Processed + original
        #expect(dataCache.writeCount == 2) // Initial + processed
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func givenNoImageDataInDiskCacheAndDiskWritesDisabled() async throws {
        // WHEN
        var request = request
        request.options.insert(.disableDiskCacheWrites)
        let response = try await pipeline.imageTask(with: request).response
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == nil)

        // THEN
        #expect(imageCache.readCount == 3) // Processed + intermediate + original
        #expect(imageCache.writeCount == 1) // Processed
        #expect(imageCache[request] != nil)
        #expect(dataCache.readCount == 3) // "1" + "2" + original
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 1)
    }
}

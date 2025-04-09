// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

/// Make sure that cache layers are checked in the correct order and the
/// minimum necessary number of cache lookups are performed.
@Suite class ImagePipelineCacheLayerPriorityTests {
    var pipeline: ImagePipeline!
    var dataLoader: MockDataLoader!
    var imageCache: MockImageCache!
    var dataCache: MockDataCache!
    var processorFactory: MockProcessorFactory!

    var request: ImageRequest!
    var intermediateRequest: ImageRequest!
    var processedImage: ImageContainer!
    var intermediateImage: ImageContainer!
    var originalRequest: ImageRequest!
    var originalImage: ImageContainer!

    init() {
        dataCache = MockDataCache()
        dataLoader = MockDataLoader()
        imageCache = MockImageCache()
        processorFactory = MockProcessorFactory()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = imageCache
            $0.debugIsSyncImageEncoding = true
        }

        request = ImageRequest(url: Test.url, processors: [
            processorFactory.make(id: "1"),
            processorFactory.make(id: "2")
        ])

        intermediateRequest = ImageRequest(url: Test.url, processors: [
            processorFactory.make(id: "1")
        ])

        originalRequest = ImageRequest(url: Test.url)

        do {
            let image = PlatformImage(data: Test.data)!
            image.nk_test_processorIDs = ["1", "2"]
            processedImage = ImageContainer(image: image)
        }

        do {
            let image = PlatformImage(data: Test.data)!
            image.nk_test_processorIDs = ["1"]
            intermediateImage = ImageContainer(image: image)
        }

        originalImage = ImageContainer(image: PlatformImage(data: Test.data)!)
    }

    @Test func givenProcessedImageInMemoryCache() async throws {
        // Given
        imageCache[request] = processedImage

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.cacheType == .memory)
        #expect(response.image === processedImage.image)

        // Then
        #expect(imageCache.readCount == 1)
        #expect(imageCache.writeCount == 1) // Initial write // Initial write
        #expect(dataCache.readCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenProcessedImageInBothMemoryAndDiskCache() async throws {
        // Given
        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.all])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.cacheType == .memory)
        #expect(response.image === processedImage.image)

        // Then
        #expect(imageCache.readCount == 1)
        #expect(imageCache.writeCount == 1) // Initial write // Initial write
        #expect(dataCache.readCount == 0)
        #expect(dataCache.writeCount == 1) // Initial write // Initial write
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenProcessedImageInDiskCache() async throws {
        // Given
        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.disk])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.cacheType == .disk)
        #expect(response.image != nil)

        // Then
        #expect(imageCache.readCount == 1)
        #expect(imageCache.writeCount == 1) // Initial write // Initial write
        #expect(dataCache.readCount == 1)
        #expect(dataCache.writeCount == 1) // Initial write // Initial write
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenProcessedImageInDiskCacheAndIndermediateImageInMemoryCache() async throws {
        // Given
        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.disk])
        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.cacheType == .disk)
        #expect(response.image != nil)

        // Then
        #expect(imageCache.readCount == 1)
        #expect(imageCache.writeCount == 2) // Initial write // Initial write
        #expect(imageCache[request] != nil)
        #expect(imageCache[intermediateRequest] != nil)
        #expect(dataCache.readCount == 1)
        #expect(dataCache.writeCount == 1) // Initial write // Initial write
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenIndermediateImageInMemoryCache() async throws {
        // Given
        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Them
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == .memory)

        // Then
        #expect(imageCache.readCount == 2) // Processed + intermediate // Processed + intermediate
        #expect(imageCache.writeCount == 2) // Initial write // Initial write
        #expect(imageCache[request] != nil)
        #expect(imageCache[intermediateRequest] != nil)
        #expect(dataCache.readCount == 1) // Check original image // Check original image
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenOriginalAndIntermediateImageInMemoryCache() async throws {
        // Given
        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.memory])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == .memory)

        // Then
        #expect(imageCache.readCount == 2) // Processed + intermediate // Processed + intermediate
        #expect(imageCache.writeCount == 3) // Initial write + write processed // Initial write + write processed
        #expect(imageCache[originalRequest] != nil)
        #expect(imageCache[request] != nil)
        #expect(imageCache[intermediateRequest] != nil)
        #expect(dataCache.readCount == 1) // Check original image // Check original image
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenOriginalImageInBothCaches() async throws {
        // Given
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.all])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == .memory)

        // Then
        #expect(imageCache.readCount == 3) // Processed + intermediate + original // Processed + intermediate + original
        #expect(imageCache.writeCount == 2) // Processed + original // Processed + original
        #expect(imageCache[originalRequest] != nil)
        #expect(imageCache[request] != nil)
        #expect(dataCache.readCount == 2) // "1", "2" // "1", "2"
        #expect(dataCache.writeCount == 1) // Initial // Initial
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func givenOriginalImageInDiskCache() async throws {
        // Given
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.disk])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == .disk)

        // Then
        #expect(imageCache.readCount == 3) // Processed + intermediate + original // Processed + intermediate + original
        #expect(imageCache.writeCount == 1) // Processed // Processed
        #expect(imageCache[request] != nil)
        #expect(dataCache.readCount == 3) // "1" + "2" + original // "1" + "2" + original
        #expect(dataCache.writeCount == 1) // Initial // Initial
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func policyStoreEncodedImagesGivenDataAlreadyStored() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
        pipeline.cache.storeCachedImage(Test.container, for: request, caches: [.disk])
        dataCache.resetCounters()
        imageCache.resetCounters()

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image != nil)
        #expect(response.cacheType == .disk)

        // Then
        #expect(imageCache.readCount == 1)
        #expect(imageCache.writeCount == 1)
        #expect(dataCache.readCount == 1)
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: ImageRequest.Options

    @Test func givenOriginalImageInDiskCacheAndDiskReadsDisabled() async throws {
        // Given
        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.disk])

        // When
        request.options.insert(.disableDiskCacheReads)
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == nil)

        // Then
        #expect(imageCache.readCount == 3) // Processed + intermediate + original // Processed + intermediate + original
        #expect(imageCache.writeCount == 1) // Processed // Processed
        #expect(imageCache[request] != nil)
        #expect(dataCache.readCount == 0) // Processed + original // Processed + original
        #expect(dataCache.writeCount == 2) // Initial + processed // Initial + processed
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func givenNoImageDataInDiskCacheAndDiskWritesDisabled() async throws {
        // When
        request.options.insert(.disableDiskCacheWrites)
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == nil)

        // Then
        #expect(imageCache.readCount == 3) // Processed + intermediate + original // Processed + intermediate + original
        #expect(imageCache.writeCount == 1) // Processed // Processed
        #expect(imageCache[request] != nil)
        #expect(dataCache.readCount == 3) // "1" + "2" + original // "1" + "2" + original
        #expect(dataCache.writeCount == 0)
        #expect(dataLoader.createdTaskCount == 1)
    }
}

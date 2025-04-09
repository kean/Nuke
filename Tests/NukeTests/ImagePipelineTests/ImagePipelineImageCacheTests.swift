// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

/// Test how well image pipeline interacts with memory cache.
@Suite
struct ImagePipelineImageCacheTests {
    var dataLoader: MockDataLoader!
    var cache: MockImageCache!
    var pipeline: ImagePipeline!

    init() async throws {
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

///// Make sure that cache layers are checked in the correct order and the
///// minimum necessary number of cache lookups are performed.
//@Suite
//struct ImagePipelineCacheLayerPriorityTests {
//    var pipeline: ImagePipeline!
//    var dataLoader: MockDataLoader!
//    var imageCache: MockImageCache!
//    var dataCache: MockDataCache!
//    var processorFactory: MockProcessorFactory!
//
//    var request: ImageRequest!
//    var intermediateRequest: ImageRequest!
//    var processedImage: ImageContainer!
//    var intermediateImage: ImageContainer!
//    var originalRequest: ImageRequest!
//    var originalImage: ImageContainer!
//
//    init() async throws {
//        super.setUp()
//
//        dataCache = MockDataCache()
//        dataLoader = MockDataLoader()
//        imageCache = MockImageCache()
//        processorFactory = MockProcessorFactory()
//
//        pipeline = ImagePipeline {
//            $0.dataLoader = dataLoader
//            $0.dataCache = dataCache
//            $0.imageCache = imageCache
//            $0.debugIsSyncImageEncoding = true
//        }
//
//        request = ImageRequest(url: Test.url, processors: [
//            processorFactory.make(id: "1"),
//            processorFactory.make(id: "2")
//        ])
//
//        intermediateRequest = ImageRequest(url: Test.url, processors: [
//            processorFactory.make(id: "1")
//        ])
//
//        originalRequest = ImageRequest(url: Test.url)
//
//        do {
//            let image = PlatformImage(data: Test.data)!
//            image.nk_test_processorIDs = ["1", "2"]
//            processedImage = ImageContainer(image: image)
//        }
//
//        do {
//            let image = PlatformImage(data: Test.data)!
//            image.nk_test_processorIDs = ["1"]
//            intermediateImage = ImageContainer(image: image)
//        }
//
//        originalImage = ImageContainer(image: PlatformImage(data: Test.data)!)
//    }
//
//    @Test func givenProcessedImageInMemoryCache() async throws {
//        // Given
//        imageCache[request] = processedImage
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image === processedImage.image)
//        #expect(record.response?.cacheType == .memory)
//
//        // Then
//        #expect(imageCache.readCount == 1)
//        #expect(imageCache.writeCount == 1) // Initial write // Initial write
//        #expect(dataCache.readCount == 0)
//        #expect(dataCache.writeCount == 0)
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func givenProcessedImageInBothMemoryAndDiskCache() async throws {
//        // Given
//        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.all])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image === processedImage.image)
//        #expect(record.response?.cacheType == .memory)
//
//        // Then
//        #expect(imageCache.readCount == 1)
//        #expect(imageCache.writeCount == 1) // Initial write // Initial write
//        #expect(dataCache.readCount == 0)
//        #expect(dataCache.writeCount == 1) // Initial write // Initial write
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func givenProcessedImageInDiskCache() async throws {
//        // Given
//        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.disk])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image != nil)
//        #expect(record.response?.cacheType == .disk)
//
//        // Then
//        #expect(imageCache.readCount == 1)
//        #expect(imageCache.writeCount == 1) // Initial write // Initial write
//        #expect(dataCache.readCount == 1)
//        #expect(dataCache.writeCount == 1) // Initial write // Initial write
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func givenProcessedImageInDiskCacheAndIndermediateImageInMemoryCache() async throws {
//        // Given
//        pipeline.cache.storeCachedImage(processedImage, for: request, caches: [.disk])
//        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image != nil)
//        #expect(record.response?.cacheType == .disk)
//
//        // Then
//        #expect(imageCache.readCount == 1)
//        #expect(imageCache.writeCount == 2) // Initial write // Initial write
//        #expect(imageCache[request] != nil)
//        #expect(imageCache[intermediateRequest] != nil)
//        #expect(dataCache.readCount == 1)
//        #expect(dataCache.writeCount == 1) // Initial write // Initial write
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func givenIndermediateImageInMemoryCache() async throws {
//        // Given
//        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image?.nk_test_processorIDs == ["1", "2"])
//        #expect(record.response?.cacheType == .memory)
//
//        // Then
//        #expect(imageCache.readCount == 2) // Processed + intermediate // Processed + intermediate
//        #expect(imageCache.writeCount == 2) // Initial write // Initial write
//        #expect(imageCache[request] != nil)
//        #expect(imageCache[intermediateRequest] != nil)
//        #expect(dataCache.readCount == 1) // Check original image // Check original image
//        #expect(dataCache.writeCount == 0)
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func givenOriginalAndIntermediateImageInMemoryCache() async throws {
//        // Given
//        pipeline.cache.storeCachedImage(intermediateImage, for: intermediateRequest, caches: [.memory])
//        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.memory])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image?.nk_test_processorIDs == ["1", "2"])
//        #expect(record.response?.cacheType == .memory)
//
//        // Then
//        #expect(imageCache.readCount == 2) // Processed + intermediate // Processed + intermediate
//        #expect(imageCache.writeCount == 3) // Initial write + write processed // Initial write + write processed
//        #expect(imageCache[originalRequest] != nil)
//        #expect(imageCache[request] != nil)
//        #expect(imageCache[intermediateRequest] != nil)
//        #expect(dataCache.readCount == 1) // Check original image // Check original image
//        #expect(dataCache.writeCount == 0)
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func givenOriginalImageInBothCaches() async throws {
//        // Given
//        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.all])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image?.nk_test_processorIDs == ["1", "2"])
//        #expect(record.response?.cacheType == .memory)
//
//        // Then
//        #expect(imageCache.readCount == 3) // Processed + intermediate + original // Processed + intermediate + original
//        #expect(imageCache.writeCount == 2) // Processed + original // Processed + original
//        #expect(imageCache[originalRequest] != nil)
//        #expect(imageCache[request] != nil)
//        #expect(dataCache.readCount == 2) // "1", "2" // "1", "2"
//        #expect(dataCache.writeCount == 1) // Initial // Initial
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func givenOriginalImageInDiskCache() async throws {
//        // Given
//        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.disk])
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image?.nk_test_processorIDs == ["1", "2"])
//        #expect(record.response?.cacheType == .disk)
//
//        // Then
//        #expect(imageCache.readCount == 3) // Processed + intermediate + original // Processed + intermediate + original
//        #expect(imageCache.writeCount == 1) // Processed // Processed
//        #expect(imageCache[request] != nil)
//        #expect(dataCache.readCount == 3) // "1" + "2" + original // "1" + "2" + original
//        #expect(dataCache.writeCount == 1) // Initial // Initial
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func policyStoreEncodedImagesGivenDataAlreadyStored() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeEncodedImages
//        }
//
//        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
//        pipeline.cache.storeCachedImage(Test.container, for: request, caches: [.disk])
//        dataCache.resetCounters()
//        imageCache.resetCounters()
//
//        // When
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image != nil)
//        #expect(record.response?.cacheType == .disk)
//
//        // Then
//        #expect(imageCache.readCount == 1)
//        #expect(imageCache.writeCount == 1)
//        #expect(dataCache.readCount == 1)
//        #expect(dataCache.writeCount == 0)
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    // MARK: ImageRequest.Options
//
//    @Test func givenOriginalImageInDiskCacheAndDiskReadsDisabled() async throws {
//        // Given
//        pipeline.cache.storeCachedImage(originalImage, for: originalRequest, caches: [.disk])
//
//        // When
//        request.options.insert(.disableDiskCacheReads)
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image?.nk_test_processorIDs == ["1", "2"])
//        #expect(record.response?.cacheType == nil)
//
//        // Then
//        #expect(imageCache.readCount == 3) // Processed + intermediate + original // Processed + intermediate + original
//        #expect(imageCache.writeCount == 1) // Processed // Processed
//        #expect(imageCache[request] != nil)
//        #expect(dataCache.readCount == 0) // Processed + original // Processed + original
//        #expect(dataCache.writeCount == 2) // Initial + processed // Initial + processed
//        #expect(dataLoader.createdTaskCount == 1)
//    }
//
//    @Test func givenNoImageDataInDiskCacheAndDiskWritesDisabled() async throws {
//        // When
//        request.options.insert(.disableDiskCacheWrites)
//        let record = expect(pipeline).toLoadImage(with: request)
//        wait()
//        #expect(record.image?.nk_test_processorIDs == ["1", "2"])
//        #expect(record.response?.cacheType == nil)
//
//        // Then
//        #expect(imageCache.readCount == 3) // Processed + intermediate + original // Processed + intermediate + original
//        #expect(imageCache.writeCount == 1) // Processed // Processed
//        #expect(imageCache[request] != nil)
//        #expect(dataCache.readCount == 3) // "1" + "2" + original // "1" + "2" + original
//        #expect(dataCache.writeCount == 0)
//        #expect(dataLoader.createdTaskCount == 1)
//    }
//}

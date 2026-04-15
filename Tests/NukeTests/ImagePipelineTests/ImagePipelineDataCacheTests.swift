// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDataCachingTests {
    let dataLoader: MockDataLoader
    let dataCache: MockDataCache
    let pipeline: ImagePipeline

    init() {
        let dataCache = MockDataCache()
        let dataLoader = MockDataLoader()
        self.dataCache = dataCache
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
    }

    // MARK: - Basics

    @Test func imageIsLoaded() async throws {
        // Given
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString] = Test.data

        // When/Then
        _ = try await pipeline.image(for: Test.request)
    }

    @Test func dataIsStoredInCache() async throws {
        // When
        _ = try await pipeline.image(for: Test.request)

        // Then
        #expect(!dataCache.store.isEmpty)
    }

    @Test func thumbnailOptionsDataCacheStoresOriginalDataByDefault() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
            $0.imageCache = MockImageCache()
        }

        // WHEN
        var request = ImageRequest(url: Test.url)
        request.thumbnail = .init(
            size: CGSize(width: 400, height: 400),
            unit: .pixels,
            contentMode: .aspectFit
        )

        _ = try await pipeline.image(for: request)

        // THEN
        do { // Check memory cache
            // Image does not exists for the original image
            #expect(pipeline.cache.cachedImage(for: ImageRequest(url: Test.url), caches: [.memory]) == nil)

            // Image exists for thumbnail
            let thumbnail = try #require(pipeline.cache.cachedImage(for: request, caches: [.memory]))
            #expect(thumbnail.image.sizeInPixels == CGSize(width: 400, height: 300))
        }

        do { // Check disk cache
            // Data exists for the original image
            let original = try #require(pipeline.cache.cachedImage(for: ImageRequest(url: Test.url), caches: [.disk]))
            #expect(original.image.sizeInPixels == CGSize(width: 640, height: 480))

            // Data does not exist for thumbnail
            #expect(pipeline.cache.cachedData(for: request) == nil)
        }
    }

    @Test func thumbnailOptionsDataCacheStoresOriginalDataWithStoreAllPolicy() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
            $0.imageCache = MockImageCache()
        }

        // WHEN
        var request = ImageRequest(url: Test.url)
        request.thumbnail = .init(
            size: CGSize(width: 400, height: 400),
            unit: .pixels,
            contentMode: .aspectFit
        )

        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        do { // Check memory cache
            // Image does not exists for the original image
            #expect(pipeline.cache.cachedImage(for: ImageRequest(url: Test.url), caches: [.memory]) == nil)

            // Image exists for thumbnail
            let thumbnail = try #require(pipeline.cache.cachedImage(for: request, caches: [.memory]))
            #expect(thumbnail.image.sizeInPixels == CGSize(width: 400, height: 300))
        }

        do { // Check disk cache
            // Data exists for the original image
            let original = try #require(pipeline.cache.cachedImage(for: ImageRequest(url: Test.url), caches: [.disk]))
            #expect(original.image.sizeInPixels == CGSize(width: 640, height: 480))

            // Data exists for thumbnail
            let thumbnail = try #require(pipeline.cache.cachedImage(for: request, caches: [.disk]))
            #expect(thumbnail.image.sizeInPixels == CGSize(width: 400, height: 300))
        }
    }

    // MARK: - Updating Priority

    @Test func priorityUpdated() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        #expect(request.priority == .normal)

        var task: ImageTask!
        let operations = await queue.waitForOperations(count: 1) {
            task = pipeline.imageTask(with: request)
        }

        // When/Then
        let operation = try #require(operations.first)
        await queue.waitForPriorityChange(of: operation, to: .high) {
            task.priority = .high
        }
    }

    // MARK: - Cancellation

    @Test func operationCancelled() async throws {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true
        var task: ImageTask!
        let operations = await queue.waitForOperations(count: 1) {
            task = pipeline.imageTask(with: Test.request)
        }

        // When/Then
        let operation = try #require(operations.first)
        await queue.waitForCancellation(of: operation) {
            task.cancel()
        }
    }

    // MARK: ImageRequest.CachePolicy

    @Test func reloadIgnoringCachedData() async throws {
        // Given
        dataCache.store[Test.url.absoluteString] = Test.data

        var request = Test.request
        request.options = [.reloadIgnoringCachedData]

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func loadFromCacheOnlyDataCache() async throws {
        // Given
        dataCache.store[Test.url.absoluteString] = Test.data

        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func loadFromCacheOnlyMemoryCache() async throws {
        // Given
        let imageCache = MockImageCache()
        imageCache[Test.request] = ImageContainer(image: Test.image)
        let pipeline = pipeline.reconfigured {
            $0.imageCache = imageCache
        }

        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func loadImageFromCacheOnlyFailsIfNoCache() async {
        // GIVEN no cached data and download disabled
        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // WHEN/THEN
        await #expect {
            _ = try await pipeline.image(for: request)
        } throws: {
            ($0 as? ImagePipeline.Error) == .dataMissingInCache
        }
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func loadDataFromCacheOnlyFailsIfNoCache() async {
        // GIVEN no cached data and download disabled
        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // WHEN/THEN
        await #expect {
            try await pipeline.data(for: request)
        } throws: {
            ($0 as? ImagePipeline.Error) == .dataMissingInCache
        }
        #expect(dataLoader.createdTaskCount == 0)
    }
}

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDataCachePolicyTests {
    let dataLoader: MockDataLoader
    let dataCache: MockDataCache
    let pipeline: ImagePipeline
    let encoder: MockImageEncoder
    let processorFactory: MockProcessorFactory
    let request: ImageRequest

    init() {
        let dataCache = MockDataCache()
        let dataLoader = MockDataLoader()
        let encoder = MockImageEncoder(result: Test.data(name: "fixture-tiny", extension: "jpeg"))
        let processorFactory = MockProcessorFactory()
        self.dataCache = dataCache
        self.dataLoader = dataLoader
        self.encoder = encoder
        self.processorFactory = processorFactory
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.makeImageEncoder = { _ in encoder }
        }
        self.request = ImageRequest(url: Test.url, processors: [processorFactory.make(id: "1")])
    }

    // MARK: - Basics

    @Test func processedImageLoadedFromDataCache() async throws {
        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        _ = try await pipeline.image(for: request)

        // Then
        #expect(processorFactory.numberOfProcessorsApplied == 0)
    }

#if !os(macOS)
    @Test func processedImageIsDecompressed() async throws {
        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        let response = try await pipeline.imageTask(with: request).response
        let image = response.image
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
    }

    @Test func processedImageIsStoredInMemoryCache() async throws {
        // Given processed image data stored in data cache
        let cache = MockImageCache()
        let pipeline = pipeline.reconfigured {
            $0.imageCache = cache
        }
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When
        _ = try await pipeline.image(for: request)

        // Then decompressed image is stored in disk cache
        let container = cache[request]
        #expect(container != nil)

        let image = try #require(container?.image)
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
    }

    @Test func processedImageNotDecompressedWhenDecompressionDisabled() async throws {
        // Given pipeline with decompression disabled
        let pipeline = pipeline.reconfigured {
            $0.isDecompressionEnabled = false
        }

        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        let response = try await pipeline.imageTask(with: request).response
        let image = response.image
        let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: image)
        #expect(isDecompressionNeeded == true)
    }
#endif

    // MARK: DataCachPolicy.automatic

    @Test func policyAutomaticGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN encoded processed image is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyAutomaticGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyAutomaticGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // WHEN
        _ = try await pipeline.image(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.image(for: ImageRequest(url: Test.url))
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        // encoded processed image is stored in disk cache
        // original image data is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 2)
        #expect(dataCache.store.count == 2)
    }

    @Test func policyAutomaticGivenOriginalImageInMemoryCache() async throws {
        // GIVEN
        let imageCache = MockImageCache()
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
            $0.imageCache = imageCache
        }
        imageCache[ImageRequest(url: Test.url)] = Test.container

        // WHEN
        _ = try await pipeline.image(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        // encoded processed image is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: DataCachPolicy.storeEncodedImages

    @Test func policyStoreEncodedImagesGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN encoded processed image is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreEncodedImagesGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreEncodedImagesGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // WHEN
        _ = try await pipeline.image(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.image(for: ImageRequest(url: Test.url))
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        // encoded processed image is stored in disk cache
        // encoded original image is stored in disk cache
        #expect(encoder.encodeCount == 2)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 2)
        #expect(dataCache.store.count == 2)
    }

    // MARK: DataCachPolicy.storeOriginalData

    @Test func policyStoreOriginalDataGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN encoded processed image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreOriginalDataGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreOriginalDataGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // WHEN
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])),
             pipeline.imageTask(with: ImageRequest(url: Test.url)))
        }
        _ = try await task1.response
        _ = try await task2.response

        // THEN
        // encoded processed image is stored in disk cache
        // encoded original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    // MARK: DataCachPolicy.storeAll

    @Test func policyStoreAllGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN encoded processed image is stored in disk cache and
        // original image data stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 2)
        #expect(dataCache.store.count == 2)
    }

    @Test func policyStoreAllGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreAllGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // WHEN
        _ = try await pipeline.image(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.image(for: ImageRequest(url: Test.url))
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        // encoded processed image is stored in disk cache
        // original image data is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 2)
        #expect(dataCache.store.count == 2)
    }

    // MARK: Local Resources

    @Test func imagesFromLocalStorageNotCached() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg"))

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func processedImagesFromLocalStorageAreCached() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg"), processors: [.resize(width: 100)])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN processed image is stored in disk cache
        #expect(encoder.encodeCount == 1)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func imagesFromMemoryNotCached() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg"))

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func imagesFromData() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let data = Test.data(name: "fixture", extension: "jpeg")
        let url = URL(string: "data:image/jpeg;base64,\(data.base64EncodedString())")
        let request = ImageRequest(url: url)

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    // MARK: Misc

    @Test func setCustomImageEncoder() async throws {
        struct MockImageEncoder: ImageEncoding, @unchecked Sendable {
            let closure: (PlatformImage) -> Data?

            func encode(_ image: PlatformImage) -> Data? {
                return closure(image)
            }
        }

        // Given
        nonisolated(unsafe) var isCustomEncoderCalled = false
        let encoder = MockImageEncoder { _ in
            isCustomEncoderCalled = true
            return nil
        }

        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
            $0.makeImageEncoder = { _ in
                return encoder
            }
        }

        // When
        _ = try await pipeline.image(for: request)

        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // Then
        #expect(isCustomEncoderCalled)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "1") == nil)
    }

    // MARK: Integration with Thumbnail Feature

    @Test func originalDataStoredWhenThumbnailRequested() async throws {
        // GIVEN
        var request = ImageRequest(url: Test.url)
        request.thumbnail = .init(maxPixelSize: 400)

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN
        #expect(dataCache.containsData(for: "http://test.com/example.jpeg"))
    }

    // MARK: - Thumbnail + Original Data Reuse

    @Test func thumbnailRequestReusesOriginalDataFromDiskCache() async throws {
        // GIVEN original image is loaded (no thumbnail), caching original data to disk
        _ = try await pipeline.image(for: Test.request)
        #expect(dataCache.containsData(for: Test.url.absoluteString))

        // WHEN a thumbnail of the same URL is requested
        var thumbnailRequest = ImageRequest(url: Test.url)
        thumbnailRequest.thumbnail = .init(maxPixelSize: 400)

        _ = try await pipeline.image(for: thumbnailRequest)

        // THEN no additional network request is made — the original data from
        // the disk cache should be reused to generate the thumbnail locally
        #expect(dataLoader.createdTaskCount == 1)
    }
}

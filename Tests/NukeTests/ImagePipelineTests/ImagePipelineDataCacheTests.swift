// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke

@ImagePipelineActor
@Suite class ImagePipelineDataCachingTests {
    var dataLoader: MockDataLoader!
    var dataCache: MockDataCache!
    var pipeline: ImagePipeline!
    var processorFactory: MockProcessorFactory!

    init() {
        dataCache = MockDataCache()
        dataLoader = MockDataLoader()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
    }

    // MARK: - Basics

    @Test func imageIsLoaded() async throws {
        // Given image in cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString] = Test.data

        // Then image is loaded
        _ = try await pipeline.image(for: Test.request)
    }

    @Test func dataIsStoredInCache() async throws {
        // When
        _ = try await pipeline.image(for: Test.request)

        // Then data is stored in disk cache
        #expect(!dataCache.store.isEmpty)
    }

    @Test func thumbnailOptionsDataCacheStoresOriginalDataByDefault() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
            $0.imageCache = MockImageCache()
            $0.debugIsSyncImageEncoding = true
        }

        // When
        let request = ImageRequest(
            url: Test.url,
            userInfo: [.thumbnailKey: ImageRequest.ThumbnailOptions(
                size: CGSize(width: 400,height: 400
                ),
                unit: .pixels,
                contentMode: .aspectFit
            )]
        )

        // Then image is loded
        _ = try await pipeline.image(for: request)

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
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
            $0.imageCache = MockImageCache()
            $0.debugIsSyncImageEncoding = true
        }

        // When
        let request = ImageRequest(
            url: Test.url,
            userInfo: [.thumbnailKey: ImageRequest.ThumbnailOptions(
                size: CGSize(width: 400,height: 400),
                unit: .pixels,
                contentMode: .aspectFit
            )]
        )

        // When
        _ = try await pipeline.image(for: request)

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

    @Test func priorityUpdated() async {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        #expect(request.priority == .normal)

        let expectation1 = queue.expectItemAdded()
        let task = pipeline.imageTask(with: request).resume()
        let workItem = await expectation1.wait()

        // When task priority is updated
        let expectation2 = queue.expectPriorityUpdated(for: workItem)
        task.priority = .high
        let newPriority = await expectation2.wait()

        // The work item is also updated
        #expect(newPriority == .high)
    }

    // MARK: - Cancellation

    @Test func operationCancelled() async {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        // When
        let expectation1 = queue.expectItemAdded()
        let task = pipeline.imageTask(with: Test.request).resume()
        let workItem = await expectation1.wait()

        // When
        let expectation2 = queue.expectItemCancelled(workItem)
        task.cancel()

        // Then
        await expectation2.wait()
    }

    // TODO: finish
//    // MARK: ImageRequest.CachePolicy
//
//    @Test func reloadIgnoringCachedData() {
//        // Given
//        dataCache.store[Test.url.absoluteString] = Test.data
//
//        var request = Test.request
//        request.options = [.reloadIgnoringCachedData]
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then
//        #expect(dataLoader.createdTaskCount == 1)
//    }
//
//    @Test func loadFromCacheOnlyDataCache() {
//        // Given
//        dataCache.store[Test.url.absoluteString] = Test.data
//
//        var request = Test.request
//        request.options = [.returnCacheDataDontLoad]
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func loadFromCacheOnlyMemoryCache() {
//        // Given
//        let imageCache = MockImageCache()
//        imageCache[Test.request] = ImageContainer(image: Test.image)
//        pipeline = pipeline.reconfigured {
//            $0.imageCache = imageCache
//        }
//
//        var request = Test.request
//        request.options = [.returnCacheDataDontLoad]
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func loadImageFromCacheOnlyFailsIfNoCache() {
//        // Given no cached data and download disabled
//        var request = Test.request
//        request.options = [.returnCacheDataDontLoad]
//
//        // When
//        expect(pipeline).toFailRequest(request, with: .dataMissingInCache)
//        wait()
//
//        // Then
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    @Test func loadDataFromCacheOnlyFailsIfNoCache() {
//        // Given no cached data and download disabled
//        var request = Test.request
//        request.options = [.returnCacheDataDontLoad]
//
//        // When
//        let output = expect(pipeline).toLoadData(with: request)
//        wait()
//
//        #expect(output.result?.error == .dataMissingInCache)
//
//        // Then
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//}
//
//@Suite
//
//struct ImagePipelineDataCachePolicyTests {
//    var dataLoader: MockDataLoader!
//    var dataCache: MockDataCache!
//    var pipeline: ImagePipeline!
//    var encoder: MockImageEncoder!
//    var processorFactory: MockProcessorFactory!
//    var request: ImageRequest!
//
//    init() {
//        super.setUp()
//
//        dataCache = MockDataCache()
//        dataLoader = MockDataLoader()
//        let encoder = MockImageEncoder(result: Test.data(name: "fixture-tiny", extension: "jpeg"))
//        self.encoder = encoder
//
//        pipeline = ImagePipeline {
//            $0.dataLoader = dataLoader
//            $0.dataCache = dataCache
//            $0.imageCache = nil
//            $0.makeImageEncoder = { _ in encoder }
//            $0.debugIsSyncImageEncoding = true
//        }
//
//        processorFactory = MockProcessorFactory()
//
//        request = ImageRequest(url: Test.url, processors: [processorFactory.make(id: "1")])
//    }
//
//    // MARK: - Basics
//
//    @Test func processedImageLoadedFromDataCache() {
//        // Given processed image data stored in data cache
//        dataLoader.queue.isSuspended = true
//        dataCache.store[Test.url.absoluteString + "1"] = Test.data
//
//        // When/Then
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then
//        #expect(processorFactory.numberOfProcessorsApplied == 0, "Expected no processors to be applied")
//    }
//
//#if !os(macOS)
//    @Test func processedImageIsDecompressed() {
//        // Given processed image data stored in data cache
//        dataLoader.queue.isSuspended = true
//        dataCache.store[Test.url.absoluteString + "1"] = Test.data
//
//        // When/Then
//        expect(pipeline).toLoadImage(with: request) { result in
//            guard let image = result.value?.image else {
//                return Issue.record("Expected image to be loaded")
//            }
//
//            #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
//        }
//        wait()
//    }
//
//    @Test func processedImageIsStoredInMemoryCache() throws {
//        // Given processed image data stored in data cache
//        let cache = MockImageCache()
//        pipeline = pipeline.reconfigured {
//            $0.imageCache = cache
//        }
//        dataLoader.queue.isSuspended = true
//        dataCache.store[Test.url.absoluteString + "1"] = Test.data
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then decompressed image is stored in disk cache
//        let container = cache[request]
//        #expect(container != nil)
//
//        let image = try #require(container?.image)
//        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
//    }
//
//    @Test func processedImageNotDecompressedWhenDecompressionDisabled() {
//        // Given pipeline with decompression disabled
//        pipeline = pipeline.reconfigured {
//            $0.isDecompressionEnabled = false
//        }
//
//        // Given processed image data stored in data cache
//        dataLoader.queue.isSuspended = true
//        dataCache.store[Test.url.absoluteString + "1"] = Test.data
//
//        // When/Then
//        expect(pipeline).toLoadImage(with: request) { result in
//            guard let image = result.value?.image else {
//                return Issue.record("Expected image to be loaded")
//            }
//
//            let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: image)
//            #expect(isDecompressionNeeded == true, "Expected image to still be marked as non decompressed")
//        }
//        wait()
//    }
//#endif
//
//    // MARK: DataCachPolicy.automatic
//
//    @Test func policyAutomaticGivenRequestWithProcessors() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//        }
//
//        // Given request with a processor
//        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then encoded processed image is stored in disk cache
//        #expect(encoder.encodeCount == 1)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policyAutomaticGivenRequestWithoutProcessors() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//        }
//
//        // Given request without a processor
//        let request = ImageRequest(url: Test.url)
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policyAutomaticGivenTwoRequests() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//        }
//
//        // When
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
//            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url))
//        }
//        wait()
//
//        // Then
//        // encoded processed image is stored in disk cache
//        // original image data is stored in disk cache
//        #expect(encoder.encodeCount == 1)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 2)
//        #expect(dataCache.store.count == 2)
//    }
//
//    @Test func policyAutomaticGivenOriginalImageInMemoryCache() {
//        // Given
//        let imageCache = MockImageCache()
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//            $0.imageCache = imageCache
//        }
//        imageCache[ImageRequest(url: Test.url)] = Test.container
//
//        // When
//        expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
//        wait()
//
//        // Then
//        // encoded processed image is stored in disk cache
//        #expect(encoder.encodeCount == 1)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//        #expect(dataLoader.createdTaskCount == 0)
//    }
//
//    // MARK: DataCachPolicy.storeEncodedImages
//
//    @Test func policyStoreEncodedImagesGivenRequestWithProcessors() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeEncodedImages
//        }
//
//        // Given request with a processor
//        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then encoded processed image is stored in disk cache
//        #expect(encoder.encodeCount == 1)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policyStoreEncodedImagesGivenRequestWithoutProcessors() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeEncodedImages
//        }
//
//        // Given request without a processor
//        let request = ImageRequest(url: Test.url)
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then
//        #expect(encoder.encodeCount == 1)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policyStoreEncodedImagesGivenTwoRequests() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeEncodedImages
//        }
//
//        // When
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
//            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url))
//        }
//        wait()
//
//        // Then
//        // encoded processed image is stored in disk cache
//        // encoded original image is stored in disk cache
//        #expect(encoder.encodeCount == 2)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 2)
//        #expect(dataCache.store.count == 2)
//    }
//
//    // MARK: DataCachPolicy.storeOriginalData
//
//    @Test func policyStoreOriginalDataGivenRequestWithProcessors() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeOriginalData
//        }
//
//        // Given request with a processor
//        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then encoded processed image is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policyStoreOriginalDataGivenRequestWithoutProcessors() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeOriginalData
//        }
//
//        // Given request without a processor
//        let request = ImageRequest(url: Test.url)
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policyStoreOriginalDataGivenTwoRequests() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeOriginalData
//        }
//
//        // When
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
//            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url))
//        }
//        wait()
//
//        // Then
//        // encoded processed image is stored in disk cache
//        // encoded original image is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    // MARK: DataCachPolicy.storeAll
//
//    @Test func policyStoreAllGivenRequestWithProcessors() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeAll
//        }
//
//        // Given request with a processor
//        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then encoded processed image is stored in disk cache and
//        // original image data stored in disk cache
//        #expect(encoder.encodeCount == 1)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 2)
//        #expect(dataCache.store.count == 2)
//    }
//
//    @Test func policyStoreAllGivenRequestWithoutProcessors() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeAll
//        }
//
//        // Given request without a processor
//        let request = ImageRequest(url: Test.url)
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policyStoreAllGivenTwoRequests() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeAll
//        }
//
//        // When
//        expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
//        expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url))
//        wait()
//
//        // Then
//        // encoded processed image is stored in disk cache
//        // original image data is stored in disk cache
//        #expect(encoder.encodeCount == 1)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") != nil)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 2)
//        #expect(dataCache.store.count == 2)
//    }
//
//    // MARK: Local Resources
//
//    @Test func imagesFromLocalStorageNotCached() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//        }
//
//        // Given request without a processor
//        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg"))
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.writeCount == 0)
//        #expect(dataCache.store.count == 0)
//    }
//
//    @Test func processedImagesFromLocalStorageAreNotCached() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//        }
//
//        // Given request with a processor
//        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg") ,processors: [.resize(width: 100)])
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.writeCount == 0)
//        #expect(dataCache.store.count == 0)
//    }
//
//    @Test func imagesFromMemoryNotCached() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//        }
//
//        // Given request without a processor
//        let request = ImageRequest(url: Test.url(forResource: "fixture", extension: "jpeg"))
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.writeCount == 0)
//        #expect(dataCache.store.count == 0)
//    }
//
//    @Test func imagesFromData() {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//        }
//
//        // Given request without a processor
//        let data = Test.data(name: "fixture", extension: "jpeg")
//        let url = URL(string: "data:image/jpeg;base64,\(data.base64EncodedString())")
//        let request = ImageRequest(url: url)
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.writeCount == 0)
//        #expect(dataCache.store.count == 0)
//    }
//
//    // MARK: Misc
//
//    @Test func setCustomImageEncoder() {
//        struct MockImageEncoder: ImageEncoding, @unchecked Sendable {
//            let closure: (PlatformImage) -> Data?
//
//            func encode(_ image: PlatformImage) -> Data? {
//                return closure(image)
//            }
//        }
//
//        // Given
//        var isCustomEncoderCalled = false
//        let encoder = MockImageEncoder { _ in
//            isCustomEncoderCalled = true
//            return nil
//        }
//
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//            $0.makeImageEncoder = { _ in
//                return encoder
//            }
//        }
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//
//        // Then
//        wait { _ in
//            #expect(isCustomEncoderCalled)
//            #expect(self.dataCache.cachedData(for: Test.url.absoluteString + "1") == nil, "Expected processed image data to not be stored")
//        }
//    }
//
//    // MARK: Integration with Thumbnail Feature
//
//    @Test func originalDataStoredWhenThumbnailRequested() {
//        // Given
//        let options = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
//        let request = ImageRequest(url: Test.url, userInfo: [.thumbnailKey: options])
//
//        // When
//        expect(pipeline).toLoadImage(with: request)
//        wait()
//
//        // Then
//        #expect(dataCache.containsData(for: "http://test.com/example.jpeg"))
//    }
}

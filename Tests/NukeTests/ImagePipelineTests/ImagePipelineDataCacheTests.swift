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

        // Then image is loaded
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

        let expectation1 = queue.expectJobAdded()
        let task = pipeline.imageTask(with: request).resume()
        let job = await expectation1.wait()

        // When task priority is updated
        let expectation2 = queue.expectPriorityUpdated(for: job)
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
        let expectation1 = queue.expectJobAdded()
        let task = pipeline.imageTask(with: Test.request).resume()
        let job = await expectation1.wait()

        // When
        let expectation2 = queue.expectJobCancelled(job)
        task.cancel()

        // Then
        await expectation2.wait()
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
        pipeline = pipeline.reconfigured {
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
        // Given no cached data and download disabled
        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // When
        do {
            _ = try await pipeline.image(for: request)
            Issue.record()
        } catch {
            #expect(error == .dataMissingInCache)
        }

        // Then
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func loadDataFromCacheOnlyFailsIfNoCache() async throws {
        // Given no cached data and download disabled
        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // When
        do {
            _ = try await pipeline.data(for: request)
            Issue.record()
        } catch {
            #expect(error == .dataMissingInCache)
        }

        // Then
        #expect(dataLoader.createdTaskCount == 0)
    }
}

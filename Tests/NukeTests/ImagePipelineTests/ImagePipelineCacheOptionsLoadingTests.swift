// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// How the request cache options and the image ID shape what the pipeline
/// reads from and writes to the caches while it loads images.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineCacheOptionsLoadingTests {
    private let dataLoader: MockDataLoader
    private let imageCache: MockImageCache
    private let dataCache: MockDataCache
    private let observer: ImagePipelineObserver
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let dataCache = MockDataCache()
        let observer = ImagePipelineObserver()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.dataCache = dataCache
        self.observer = observer
        self.pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
    }

    // MARK: returnCacheDataDontLoad

    @Test func returnCacheDataDontLoadServesTheProcessedImageFromTheDisk() async throws {
        // GIVEN the processed image in the disk cache
        let request = ImageRequest(
            url: Test.url,
            processors: [MockImageProcessor(id: "1"), MockImageProcessor(id: "2")],
            options: [.returnCacheDataDontLoad]
        )
        dataCache.store[Test.url.absoluteString + "12"] = Test.data

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN it's decoded as is, without loading or processing anything
        #expect(response.image.nk_test_processorIDs == [])
        #expect(response.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 0)
        #expect(pipeline.cache[request] != nil)
    }

    @Test func returnCacheDataDontLoadCreatesTheThumbnailFromTheOriginalData() async throws {
        // GIVEN only the original data in the disk cache
        dataCache.store[Test.url.absoluteString] = Test.data
        let request = ImageRequest(url: Test.url, options: [.returnCacheDataDontLoad]).with {
            $0.thumbnail = .init(maxPixelSize: 100)
        }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.sizeInPixels == CGSize(width: 100, height: 75))
        #expect(response.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func returnCacheDataDontLoadCreatesTheThumbnailFromTheOriginalDataWhenItsEntryCantBeDecoded() async throws {
        // GIVEN a corrupted thumbnail entry and the original data in the disk cache
        let request = ImageRequest(url: Test.url, options: [.returnCacheDataDontLoad]).with {
            $0.thumbnail = .init(maxPixelSize: 100)
        }
        dataCache.store[pipeline.cache.makeDataCacheKey(for: request)] = Data("corrupted".utf8)
        dataCache.store[Test.url.absoluteString] = Test.data

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.sizeInPixels == CGSize(width: 100, height: 75))
        #expect(response.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func returnCacheDataDontLoadProcessesTheOriginalDataFromTheDisk() async throws {
        // GIVEN only the original data in the disk cache
        dataCache.store[Test.url.absoluteString] = Test.data
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], options: [.returnCacheDataDontLoad])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.nk_test_processorIDs == ["1"])
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func returnCacheDataDontLoadProcessesTheOriginalImageFromMemory() async throws {
        // GIVEN only the original image in the memory cache
        pipeline.cache[Test.request] = Test.container
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], options: [.returnCacheDataDontLoad])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.nk_test_processorIDs == ["1"])
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func returnCacheDataDontLoadProcessesTheIntermediateImageFromMemory() async throws {
        // GIVEN only the intermediate image in the memory cache
        pipeline.cache[ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])] = Test.container
        let request = ImageRequest(
            url: Test.url,
            processors: [MockImageProcessor(id: "1"), MockImageProcessor(id: "2")],
            options: [.returnCacheDataDontLoad]
        )

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN only the last processor is applied
        #expect(response.image.nk_test_processorIDs == ["2"])
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func returnCacheDataDontLoadFailsProcessedRequestWhenNothingIsCached() async throws {
        // GIVEN empty caches
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")], options: [.returnCacheDataDontLoad])

        // WHEN/THEN
        await #expect(throws: ImagePipeline.Error.dataMissingInCache) {
            try await pipeline.imageTask(with: request).response
        }
        #expect(dataLoader.createdTaskCount == 0)
    }

    /// A progressive preview in the memory cache is delivered, but it isn't
    /// the image, so the request still fails when there is nothing else.
    @Test func returnCacheDataDontLoadFailsAfterDeliveringTheCachedPreview() async throws {
        // GIVEN
        let preview = ImageContainer(image: Test.image, isPreview: true)
        pipeline.cache[Test.request] = preview
        let request = ImageRequest(url: Test.url, options: [.returnCacheDataDontLoad])

        // WHEN
        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: observer)
        await #expect(throws: ImagePipeline.Error.dataMissingInCache) {
            try await pipeline.imageTask(with: request).response
        }
        await completed.wait()

        // THEN
        let previewResponse = ImageResponse(container: preview, request: request, cacheType: .memory)
        #expect(observer.events == [
            .created,
            .started,
            .intermediateResponseReceived(response: previewResponse),
            .completed(result: .failure(.dataMissingInCache))
        ])
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func cachedPreviewIsFollowedByTheImageFromTheDisk() async throws {
        // GIVEN a preview in the memory cache and the data on the disk
        let preview = ImageContainer(image: Test.image, isPreview: true)
        pipeline.cache[Test.request] = preview
        dataCache.store[Test.url.absoluteString] = Test.data

        // WHEN
        let completed = TestExpectation(notification: ImagePipelineObserver.didCompleteTask, object: observer)
        let response = try await pipeline.imageTask(with: Test.request).response
        await completed.wait()

        // THEN the preview is delivered first, then the final image
        let previewResponse = ImageResponse(container: preview, request: Test.request, cacheType: .memory)
        #expect(observer.events == [
            .created,
            .started,
            .intermediateResponseReceived(response: previewResponse),
            .completed(result: .success(response))
        ])
        #expect(response.image !== preview.image)
        #expect(!response.container.isPreview)
        #expect(response.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 0)

        // THEN the final image replaces the preview in the memory cache
        let cached = try #require(pipeline.cache[Test.request])
        #expect(!cached.isPreview)
    }

    // MARK: Memory Cache Options

    /// The options apply to every stage of the processing, so the pipeline
    /// doesn't pick up an intermediate result from the memory cache either.
    @Test func disableMemoryCacheReadsAppliesToTheIntermediateResults() async throws {
        // GIVEN the original and a partially processed image in memory
        pipeline.cache[Test.request] = Test.container
        pipeline.cache[ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])] = Test.container
        let request = ImageRequest(
            url: Test.url,
            processors: [MockImageProcessor(id: "1"), MockImageProcessor(id: "2")],
            options: [.disableMemoryCacheReads]
        )

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.nk_test_processorIDs == ["1", "2"])
        #expect(response.cacheType == nil)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func reloadIgnoringCachedDataRefreshesBothLayers() async throws {
        // GIVEN stale entries in both layers
        let stale = ImageContainer(image: Test.image)
        pipeline.cache[Test.request] = stale
        let staleData = Data("stale".utf8)
        dataCache.store[Test.url.absoluteString] = staleData
        let request = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN the fresh image replaces the stale one in both layers
        #expect(response.cacheType == nil)
        #expect(dataLoader.createdTaskCount == 1)
        let cached = try #require(pipeline.cache[Test.request])
        #expect(cached.image !== stale.image)
        #expect(cached.image === response.image)
        #expect(dataCache.store[Test.url.absoluteString] == Test.data)
    }

    // MARK: Closure Requests

    /// Documented: the data returned by the closure is stored in the disk
    /// cache, keyed by the request ID.
    @Test func closureDataIsStoredInTheDiskCacheUnderTheID() async throws {
        // GIVEN
        let calls = Ref(0)
        let lock = NSLock()
        let makeRequest = {
            ImageRequest(id: "photo-1", data: {
                lock.withLock { calls.value += 1 }
                return Test.data
            }, options: [.disableMemoryCache])
        }

        // WHEN
        _ = try await pipeline.image(for: makeRequest())

        // THEN
        #expect(dataCache.store == ["photo-1": Test.data])

        // WHEN the image is requested again
        let response = try await pipeline.imageTask(with: makeRequest()).response

        // THEN it is served from the disk without calling the closure
        #expect(response.cacheType == .disk)
        #expect(lock.withLock { calls.value } == 1)
    }

    // MARK: Image ID

    /// Documented: the image ID can strip the transient query parameters
    /// from the cache key.
    @Test func requestsWithTheSameImageIDShareTheCachedImage() async throws {
        // GIVEN
        let first = ImageRequest(url: URL(string: "http://test.com/example.jpeg?token=1")).with { $0.imageID = "example" }
        let second = ImageRequest(url: URL(string: "http://test.com/example.jpeg?token=2")).with { $0.imageID = "example" }

        // WHEN
        _ = try await pipeline.image(for: first)
        let response = try await pipeline.imageTask(with: second).response

        // THEN
        #expect(response.cacheType == .memory)
        #expect(dataLoader.createdTaskCount == 1)
        #expect(dataCache.store.keys.sorted() == ["example"])

        // WHEN the memory cache is cleared
        pipeline.cache.removeAll(caches: [.memory])
        let third = ImageRequest(url: URL(string: "http://test.com/example.jpeg?token=3")).with { $0.imageID = "example" }
        let fromDisk = try await pipeline.imageTask(with: third).response

        // THEN the disk cache is shared as well
        #expect(fromDisk.cacheType == .disk)
        #expect(dataLoader.createdTaskCount == 1)
    }

    /// The URL, not the image ID, determines what gets downloaded, so the
    /// concurrent requests for the different URLs aren't coalesced.
    @Test func concurrentRequestsWithTheSameImageIDButDifferentURLsAreLoadedSeparately() async throws {
        // GIVEN
        let first = ImageRequest(url: URL(string: "http://test.com/example.jpeg?token=1")).with { $0.imageID = "example" }
        let second = ImageRequest(url: URL(string: "http://test.com/example.jpeg?token=2")).with { $0.imageID = "example" }

        // WHEN
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: first), pipeline.imageTask(with: second))
        }
        _ = try await task1.response
        _ = try await task2.response

        // THEN
        #expect(dataLoader.createdTaskCount == 2)
        #expect(dataCache.store.keys.sorted() == ["example"])
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

@available(*, deprecated, message: "Just testing deprecation here")
class DeprecationTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var dataCache: MockDataCache!
    var pipeline: ImagePipeline!
    var encoder: MockImageEncoder!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        dataCache = MockDataCache()
        encoder = MockImageEncoder(result: Test.data)
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.makeImageEncoder = { [unowned self] _ in self.encoder }
            $0.debugIsSyncImageEncoding = true
        }
    }

    func testCacheLookupWithReloadPolicyImageStored() {
        // GIVEN
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        let request = ImageRequest(url: Test.url, cachePolicy: .reloadIgnoringCachedData)
        let record = expect(pipeline).toLoadData(with: request)
        wait()

        // THEN
        XCTAssertEqual(dataCache.readCount, 0)
        XCTAssertEqual(dataCache.writeCount, 2) // Initial write + write after fetch
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(record.data)
    }
}

@available(*, deprecated, message: "Just testing deprecation here")
class DeprecationsImagePipelineImageCacheTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var cache: MockImageCache!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        cache = MockImageCache()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
        }
    }

    func testReloadIgnoringCacheData() {
        // Given
        cache[Test.request] = ImageContainer(image: Test.image)

        var request = Test.request
        request.cachePolicy = .reloadIgnoringCachedData

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache[Test.request])
    }
}

@available(*, deprecated, message: "Just testing deprecation here")
class DeprecationsImagePipelineCoalescingTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var observations = [NSKeyValueObservation]()

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    func testThatDataOnlyLoadedOnceWithDifferentCachePolicy() {
        // Given
        let dataCache = MockDataCache()
        pipeline = pipeline.reconfigured {
            $0.dataCache = dataCache
        }
        dataLoader.queue.isSuspended = true

        // When
        func makeRequest(cachePolicy: ImageRequest.CachePolicy) -> ImageRequest {
            ImageRequest(urlRequest: URLRequest(url: Test.url), cachePolicy: cachePolicy)
        }
        expect(pipeline).toLoadImage(with: makeRequest(cachePolicy: .default))
        expect(pipeline).toLoadImage(with: makeRequest(cachePolicy: .reloadIgnoringCachedData))
        pipeline.queue.sync {}
        dataLoader.queue.isSuspended = false

        // Then
        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1, "Expected only one data task to be performed")
        }
    }

    func testThatDataOnlyLoadedOnceWithDifferentCachePolicyPassingURL() {
        // Given
        let dataCache = MockDataCache()
        pipeline = pipeline.reconfigured {
            $0.dataCache = dataCache
        }
        dataLoader.queue.isSuspended = true

        // When
        // - One request reloading cache data, another one not
        func makeRequest(cachePolicy: ImageRequest.CachePolicy) -> ImageRequest {
            ImageRequest(url: Test.url, cachePolicy: cachePolicy)
        }
        expect(pipeline).toLoadImage(with: makeRequest(cachePolicy: .default))
        expect(pipeline).toLoadImage(with: makeRequest(cachePolicy: .reloadIgnoringCachedData))
        pipeline.queue.sync {}
        dataLoader.queue.isSuspended = false

        // Then
        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1, "Expected only one data task to be performed")
        }
    }
}

@available(*, deprecated, message: "Just testing deprecation here")
class DeprecationsImagePipelineCacheTests: XCTestCase {
    var memoryCache: MockImageCache!
    var diskCache: MockDataCache!
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var cache: ImagePipeline.Cache { pipeline.cache }

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        diskCache = MockDataCache()
        memoryCache = MockImageCache()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = memoryCache
            $0.dataCache = diskCache
        }
    }

    func testGetCachedImageDefaultFromMemoryCacheWhenCachePolicyPreventsLookup() {
        // GIVEN
        var request = Test.request
        memoryCache[cache.makeImageCacheKey(for: request)] = Test.container

        // WHEN
        request.cachePolicy = .reloadIgnoringCachedData
        let image = cache.cachedImage(for: request)

        // THEN
        XCTAssertNil(image)
    }

    func testGetCachedImageDefaultFromDiskCacheWhenCachePolicyPreventsLookup() {
        // GIVEN
        var request = Test.request
        diskCache.storeData(Test.data, for: cache.makeDataCacheKey(for: request))

        // WHEN
        request.cachePolicy = .reloadIgnoringCachedData
        let image = cache.cachedImage(for: request, caches: [.disk])

        // THEN
        XCTAssertNil(image)
    }
}

@available(*, deprecated, message: "Just testing deprecation here")
class DeprecationsImagePipelineDataCachingTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var dataCache: MockDataCache!
    var pipeline: ImagePipeline!
    var processorFactory: MockProcessorFactory!

    override func setUp() {
        super.setUp()

        dataCache = MockDataCache()
        dataLoader = MockDataLoader()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }
    }

    func testReloadIgnoringCacheData() {
        // Given
        dataCache.store[Test.url.absoluteString] = Test.data

        var request = Test.request
        request.cachePolicy = .reloadIgnoringCachedData

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
    }

    func testLoadFromCacheOnlyDataCache() {
        // Given
        dataCache.store[Test.url.absoluteString] = Test.data

        var request = Test.request
        request.cachePolicy = .returnCacheDataDontLoad

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    func testLoadFromCacheOnlyMemoryCache() {
        // Given
        let imageCache = MockImageCache()
        imageCache[Test.request] = ImageContainer(image: Test.image)
        pipeline = pipeline.reconfigured {
            $0.imageCache = imageCache
        }

        var request = Test.request
        request.cachePolicy = .returnCacheDataDontLoad

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    func testLoadFromCacheOnlyFailsIfNoMemoryCache() {
        // Given no cache
        var request = Test.request
        request.cachePolicy = .returnCacheDataDontLoad

        // When
        expect(pipeline).toFailRequest(request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }
}

@available(*, deprecated, message: "Just testing deprecation here")
class DeprecationsImagePipelineProcessedDataCachingTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var dataCache: MockDataCache!
    var pipeline: ImagePipeline!
    var processorFactory: MockProcessorFactory!
    var request: ImageRequest!

    override func setUp() {
        super.setUp()

        dataCache = MockDataCache()
        dataLoader = MockDataLoader()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.dataCacheOptions.storedItems = [.originalImageData, .finalImage]
            $0.imageCache = nil
        }

        processorFactory = MockProcessorFactory()

        request = ImageRequest(url: Test.url, processors: [processorFactory.make(id: "1")])
    }

    // MARK: - Basics

    func testProcessedImageLoadedFromDataCache() {
        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(processorFactory.numberOfProcessorsApplied, 0, "Expected no processors to be applied")
    }

    #if !os(macOS)
    func testProcessedImageIsDecompressed() {
        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        expect(pipeline).toLoadImage(with: request) { result in
            guard let image = result.value?.image else {
                return XCTFail("Expected image to be loaded")
            }

            let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: image)
            XCTAssertNil(isDecompressionNeeded)
        }
        wait()
    }

    func testProcessedImageIsStoredInMemoryCache() throws {
        // Given processed image data stored in data cache
        let cache = MockImageCache()
        pipeline = pipeline.reconfigured {
            $0.imageCache = cache
        }
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then decompressed image is stored in disk cache
        let container = cache[self.request]
        XCTAssertNotNil(container)

        let image = try XCTUnwrap(container?.image)
        let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: image)
        XCTAssertNil(isDecompressionNeeded)
    }

    func testProcessedImageNotDecompressedWhenDecompressionDisabled() {
        // Given pipeline with decompression disabled
        pipeline = pipeline.reconfigured {
            $0.isDecompressionEnabled = false
        }

        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        expect(pipeline).toLoadImage(with: request) { result in
            guard let image = result.value?.image else {
                return XCTFail("Expected image to be loaded")
            }

            let isDecompressionNeeded = ImageDecompression.isDecompressionNeeded(for: image)
            XCTAssertEqual(isDecompressionNeeded, true, "Expected image to still be marked as non decompressed")
        }
        wait()
    }
    #endif

    func testBothProcessedAndOriginalImageDataStoredInDataCache() {
        // When
        pipeline.configuration.imageEncodingQueue.isSuspended = true
        expect(pipeline.configuration.imageEncodingQueue).toFinishWithEnqueuedOperationCount(1)
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString), "Expected original image data to be stored")
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString + "1"), "Expected processed image data to be stored")
        XCTAssertEqual(dataCache.store.count, 2)
    }

    func testOriginalDataNotStoredWhenStorageDisabled() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCacheOptions.storedItems = [.finalImage]
        }

        // When
        pipeline.configuration.imageEncodingQueue.isSuspended = true
        expect(pipeline.configuration.imageEncodingQueue).toFinishWithEnqueuedOperationCount(1)
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        let key = pipeline.cacheKey(for: request, item: .finalImage)
        XCTAssertNotNil(dataCache.cachedData(for: key), "Expected processed image data to be stored")
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testOriginalImageDataIsStoredIfNoProcessorSpecified() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCacheOptions.storedItems = [.finalImage]
        }

        // Given request without processors
        let request = ImageRequest(url: Test.url)

        // When
        pipeline.configuration.imageEncodingQueue.isSuspended = true
        expect(pipeline.configuration.imageEncodingQueue).toFinishWithEnqueuedOperationCount(1)
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        let key = pipeline.cacheKey(for: request, item: .originalImageData)
        XCTAssertNotNil(dataCache.cachedData(for: key), "Expected processed image data to be stored")
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testProcessedDataNotStoredWhenStorageDisabled() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCacheOptions.storedItems = [.originalImageData]
        }

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString), "Expected original image data to be stored")
        XCTAssertEqual(dataCache.store.count, 1)
    }
}

@available(*, deprecated, message: "Just testing deprecation here")
class DeprecationsImagePipelineObservingTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    private var observer: MockImagePipelineObserver!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        observer = MockImagePipelineObserver()
        pipeline.observer = observer
    }

    // MARK: - Completion

    func testStartAndCompletedEvents() throws {
        var result: Result<ImageResponse, ImagePipeline.Error>?
        expect(pipeline).toLoadImage(with: Test.request) { result = $0 }
        wait()

        // Then
        XCTAssertEqual(observer.events, [
            ImageTaskEvent.started,
            .progressUpdated(completedUnitCount: 22789, totalUnitCount: -1),
            .completed(result: try XCTUnwrap(result))
        ])
    }

    func testProgressUpdateEvents() throws {
        let request = ImageRequest(url: Test.url)
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        var result: Result<ImageResponse, ImagePipeline.Error>?
        expect(pipeline).toFailRequest(request) { result = $0 }
        wait()

        // Then
        XCTAssertEqual(observer.events, [
            ImageTaskEvent.started,
            .progressUpdated(completedUnitCount: 10, totalUnitCount: 20),
            .progressUpdated(completedUnitCount: 20, totalUnitCount: 20),
            .completed(result: try XCTUnwrap(result))
        ])
    }

    func testUpdatePriorityEvents() {
        // Given
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        XCTAssertEqual(request.priority, .normal)

        let operationQueueObserver = self.expect(queue).toEnqueueOperationsWithCount(1)

        let task = pipeline.loadImage(with: request) { _ in }
        wait() // Wait till the operation is created.

        guard let operation = operationQueueObserver.operations.first else {
            return XCTFail("Failed to find operation")
        }
        expect(operation).toUpdatePriority()
        task.priority = .high
        wait()

        // Then
        XCTAssertEqual(observer.events, [
            ImageTaskEvent.started,
            .priorityUpdated(priority: .high)
        ])
    }

    func testCancellationEvents() {
        dataLoader.queue.isSuspended = true

        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        let task = pipeline.loadImage(with: Test.request) { _ in
            XCTFail()
        }
        wait() // Wait till operation is created

        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        task.cancel()
        wait()

        // Then
        XCTAssertEqual(observer.events, [
            ImageTaskEvent.started,
            .cancelled
        ])
    }
}

@available(*, deprecated, message: "Just testing deprecation here")
private final class MockImagePipelineObserver: ImagePipelineObserving {
    var events = [ImageTaskEvent]()

    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent) {
        events.append(event)
    }
}

class NewImageRequestTests: XCTestCase {
    // The compiler picks up the new version
    func testInit() {
        _ = ImageRequest(url: Test.url)
        _ = ImageRequest(url: Test.url, processors: [])
        _ = ImageRequest(url: Test.url, processors: [])
        _ = ImageRequest(url: Test.url, priority: .high)
        _ = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
    }
}

@available(*, deprecated, message: "Just testing deprecation here")
class DeprecationsImageRequestsTests: XCTestCase {
    func testInit() {
        // This won't compile because `cachePolicy` is required and it has to
        // be to keep the initializers unambiguous.
        // let _ = ImageRequest(url: Test.url, options: .init(filteredURL: "aaa"))

        // But this will
        let _ = ImageRequest(url: Test.url, processors: [ImageProcessors.Circle()], cachePolicy: .returnCacheDataDontLoad)
        let _ = ImageRequest(url: Test.url, cachePolicy: .returnCacheDataDontLoad, options: ImageRequestOptions(filteredURL: "aaa"))
        let _ = ImageRequest(url: Test.url, cachePolicy: .returnCacheDataDontLoad, options: .init(filteredURL: "aaa"))
    }

    func testInitWithDeprecatedCachePolicy1() {
        // WHEN
        let request = ImageRequest(url: Test.url, cachePolicy: .default)

        // THEN
        XCTAssertEqual(request.options, [])
    }

    func testInitWithDeprecatedCachePolicy2() {
        // WHEN
        let request = ImageRequest(url: Test.url, cachePolicy: .returnCacheDataDontLoad)

        // THEN
        XCTAssertEqual(request.options, [.returnCacheDataDontLoad])
    }

    func testInitWithDeprecatedCachePolicy3() {
        // WHEN
        let request = ImageRequest(url: Test.url, cachePolicy: .reloadIgnoringCachedData)

        // THEN
        XCTAssertEqual(request.options, [.reloadIgnoringCachedData])
    }

    func testSetDeprecatedCachePolicy1() {
        // WHEN
        var request = ImageRequest(url: Test.url)
        request.cachePolicy = .default

        // THEN
        XCTAssertEqual(request.options, [])
    }

    func testSetDeprecatedCachePolicy2() {
        // WHEN
        var request = ImageRequest(url: Test.url)
        request.cachePolicy = .returnCacheDataDontLoad

        // THEN
        XCTAssertEqual(request.options, [.returnCacheDataDontLoad])
    }

    func testSetDeprecatedCachePolicy3() {
        // WHEN
        var request = ImageRequest(url: Test.url)
        request.cachePolicy = .reloadIgnoringCachedData

        // THEN
        XCTAssertEqual(request.options, [.reloadIgnoringCachedData])
    }

    func testInitWithFilteredURL() {
        // GIVEN
        let request = ImageRequest(url: Test.url, cachePolicy: .default, options: ImageRequestOptions(filteredURL: "key"))

        // THEN
        XCTAssertEqual(request.userInfo[.imageIdKey] as? String, "key")
    }

    func testInitWithMemoryCacheOptionsReadDisabled() {
        // GIVEN
        let request = ImageRequest(url: Test.url, cachePolicy: .default, options: ImageRequestOptions(memoryCacheOptions: .init(isReadAllowed: false)))

        // THEN
        XCTAssertEqual(request.options, [.disableMemoryCacheReads])
    }

    func testInitWithMemoryCacheOptionsWriteDisabled() {
        // GIVEN
        let request = ImageRequest(url: Test.url, cachePolicy: .default, options: ImageRequestOptions(memoryCacheOptions: .init(isWriteAllowed: false)))

        // THEN
        XCTAssertEqual(request.options, [.disableMemoryCacheWrites])
    }

    func testInitWithMemoryCacheOptionsWriteDisabledAndCachePolicy() {
        // GIVEN
        let request = ImageRequest(url: Test.url, cachePolicy: .reloadIgnoringCachedData, options: ImageRequestOptions(memoryCacheOptions: .init(isWriteAllowed: false)))

        // THEN
        XCTAssertEqual(request.options, [.reloadIgnoringCachedData, .disableMemoryCacheWrites])
    }
}

@available(*, deprecated, message: "Just testing deprecation here")
class DeprecationsImagePipelineDefaultProcessorsTests: XCTestCase {
    var imageCache: MockImageCache!
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        imageCache = MockImageCache()
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.processors = [MockImageProcessor(id: "p1")]
        }
    }

    // MARK: ImagePipeline loadImage()

    func testDefaultProcessorsAreApplied() {
        // GIVEN
        let request = ImageRequest(url: Test.url)

        // WHEN
        expect(pipeline).toLoadImage(with: request) { result in
            // THEN
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["p1"])
        }
        wait()
    }

    func testDefaultProcessorsAppliedWhenNilPassed() {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: nil)

        // WHEN
        expect(pipeline).toLoadImage(with: request) { result in
            // THEN
            let image = result.value?.image
            XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["p1"])
        }
        wait()
    }

    // MARK: Other Scenarios

    func testImageViewExtensionUsesDefaultProcessorForCacheLookup() {
        // GIVEN
        let view = _ImageView()
        imageCache[ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])] = Test.container

        // WHEN
        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        let task = Nuke.loadImage(with: Test.request, options: options, into: view)

        // THEN image found in memory cache
        XCTAssertNil(task)
        XCTAssertNotNil(view.image)
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
    func testImagePublisherUsesDefaultProcessorsForCacheLookup() {
        // GIVEN
        imageCache[ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])] = Test.container

        // WHEN
        let publisher = pipeline.imagePublisher(with: Test.url)
        var response: ImageResponse?
        _ = publisher.sink(receiveCompletion: { _ in }, receiveValue: {
            response = $0
        })

        // THEN image found in memory cache
        XCTAssertNotNil(response)
    }

    func testImagePipelineCacheDoesntUseDefaultProcessorForCacheLookup() {
        // GIVEN
        let cachedRequest = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
        imageCache[cachedRequest] = Test.container

        // WHEN
        let cachedImage = pipeline.cache[Test.url]

        // THEN
        XCTAssertNil(cachedImage?.image)
    }
}


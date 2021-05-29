// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineDataCachingTests: XCTestCase {
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

    // MARK: - Basics

    func testImageIsLoaded() {
        // Given
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString] = Test.data

        // When/Then
        expect(pipeline).toLoadImage(with: Test.request)
        wait()
    }

    func testDataIsStoredInCache() {
        // When
        expect(pipeline).toLoadImage(with: Test.request)

        // Then
        wait { _ in
            XCTAssertFalse(self.dataCache.store.isEmpty)
        }
    }

    // MARK: - Updating Priority

    func testPriorityUpdated() {
        // Given
        let queue = pipeline.configuration.dataCachingQueue
        queue.isSuspended = true

        let request = Test.request
        XCTAssertEqual(request.priority, .normal)

        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)

        let task = pipeline.loadImage(with: request) { _ in }
        wait() // Wait till the operation is created.

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("No operations gor registered")
        }
        expect(operation).toUpdatePriority()
        task.priority = .high

        wait()
    }

    // MARK: - Cancellation

    func testOperationCancelled() {
        // Given
        let queue = pipeline.configuration.dataCachingQueue
        queue.isSuspended = true
        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)
        let task = pipeline.loadImage(with: Test.request) { _ in }
        wait() // Wait till the operation is created.

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("No operations gor registered")
        }
        expect(operation).toCancel()
        task.cancel()
        wait() // Wait till operation is created
    }

    // MARK: ImageRequest.CachePolicy

    func testReloadIgnoringCacheData() {
        // Given
        dataCache.store[Test.url.absoluteString] = Test.data

        var request = Test.request
        request.options = [.reloadIgnoringCachedData]

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
        request.options = [.returnCacheDataDontLoad]

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
        request.options = [.returnCacheDataDontLoad]

        // When
        expect(pipeline).toLoadImage(with: request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    func testLoadFromCacheOnlyFailsIfNoMemoryCache() {
        // Given no cache
        var request = Test.request
        request.options = [.returnCacheDataDontLoad]

        // When
        expect(pipeline).toFailRequest(request)
        wait()

        // Then
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }
}

class ImagePipelineDataCachePolicyTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var dataCache: MockDataCache!
    var pipeline: ImagePipeline!
    var encoder: MockImageEncoder!
    var processorFactory: MockProcessorFactory!
    var request: ImageRequest!

    override func setUp() {
        super.setUp()

        dataCache = MockDataCache()
        dataLoader = MockDataLoader()
        encoder = MockImageEncoder(result: Test.data(name: "fixture-tiny", extension: "jpeg"))

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.makeImageEncoder = { [unowned self] _ in self.encoder }
            $0.debugIsSyncImageEncoding = true
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

            XCTAssertNil(ImageDecompression.isDecompressionNeeded(for: image))
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
        let container = cache[request]
        XCTAssertNotNil(container)

        let image = try XCTUnwrap(container?.image)
        XCTAssertNil(ImageDecompression.isDecompressionNeeded(for: image))
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

    // MARK: DataCachPolicy.automatic

    func testPolicyAutomaticGivenRequestWithProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN encoded processed image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 1)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicyAutomaticGivenRequestWithoutProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicyAutomaticGivenTwoRequests() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // WHEN
        pipeline.resgiterMultipleRequests {
            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url))
        }
        wait()

        // THEN
        // encoded processed image is stored in disk cache
        // original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 1)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 2)
        XCTAssertEqual(dataCache.store.count, 2)
    }

    func testPolicyAutomaticGivenOriginalImageInMemoryCache() {
        // GIVEN
        let imageCache = MockImageCache()
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
            $0.imageCache = imageCache
        }
        imageCache[ImageRequest(url: Test.url)] = Test.container

        // WHEN
        expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        wait()

        // THEN
        // encoded processed image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 1)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
    }

    // MARK: DataCachPolicy.storeEncodedImages

    func testPolicyStoreEncodedImagesGivenRequestWithProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN encoded processed image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 1)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString+"p1"))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicyStoreEncodedImagesGivenRequestWithoutProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN
        XCTAssertEqual(encoder.encodeCount, 1)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicyStoreEncodedImagesGivenTwoRequests() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // WHEN
        pipeline.resgiterMultipleRequests {
            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url))
        }
        wait()

        // THEN
        // encoded processed image is stored in disk cache
        // encoded original image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 2)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 2)
        XCTAssertEqual(dataCache.store.count, 2)
    }

    // MARK: DataCachPolicy.storeOriginalData

    func testPolicystoreOriginalDataGivenRequestWithProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN encoded processed image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicystoreOriginalDataGivenRequestWithoutProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicystoreOriginalDataGivenTwoRequests() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // WHEN
        pipeline.resgiterMultipleRequests {
            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
            expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url))
        }
        wait()

        // THEN
        // encoded processed image is stored in disk cache
        // encoded original image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    // MARK: DataCachPolicy.storeAll

    func testPolicyStoreAllGivenRequestWithProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN encoded processed image is stored in disk cache and
        // orginal image data stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 1)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 2)
        XCTAssertEqual(dataCache.store.count, 2)
    }

    func testPolicyStoreAllGivenRequestWithoutProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicyStoreAllGivenTwoRequests() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // WHEN
        expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        expect(pipeline).toLoadImage(with: ImageRequest(url: Test.url))
        wait()

        // THEN
        // encoded processed image is stored in disk cache
        // original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 1)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 2)
        XCTAssertEqual(dataCache.store.count, 2)
    }

    // MARK: Local Storage

    func testImagesFromLocalStorageNotCached() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: URL(string: "file://example/image.jpeg"))

        // WHEN
        expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataCache.store.count, 0)
    }

    func testImagesFromMemoryNotCached() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: URL(string: "data://example/image.jpeg"))

        // WHEN
        expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataCache.store.count, 0)
    }

    // MARK Misc

    func testSetCustomImageEncoder() {
        struct MockImageEncoder: ImageEncoding {
            let closure: (PlatformImage) -> Data?

            func encode(_ image: PlatformImage) -> Data? {
                return closure(image)
            }
        }

        // Given
        var isCustomEncoderCalled = false
        let encoder = MockImageEncoder { _ in
            isCustomEncoderCalled = true
            return nil
        }

        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
            $0.makeImageEncoder = { _ in
                return encoder
            }
        }

        // When
        expect(pipeline).toLoadImage(with: request)

        // Then
        wait { _ in
            XCTAssertTrue(isCustomEncoderCalled)
            XCTAssertNil(self.dataCache.cachedData(for: Test.url.absoluteString + "1"), "Expected processed image data to not be stored")
        }
    }
}

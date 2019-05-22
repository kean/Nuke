// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineDataCachingTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var dataCache: MockDataCache!
    var pipeline: ImagePipeline!

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

        let task = pipeline.loadImage(with: request)
        wait() // Wait till the operation is created.

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("No operations gor registered")
        }
        expect(operation).toUpdatePriority()
        task.setPriority(.high)

        wait()
    }

    // MARK: - Cancellation

    func testOperationCancelled() {
        // Given
        let queue = pipeline.configuration.dataCachingQueue
        queue.isSuspended = true
        let observer = self.expect(queue).toEnqueueOperationsWithCount(1)
        let task = pipeline.loadImage(with: Test.request)
        wait() // Wait till the operation is created.

        // When/Then
        guard let operation = observer.operations.first else {
            return XCTFail("No operations gor registered")
        }
        expect(operation).toCancel()
        task.cancel()
        wait() // Wait till operation is created
    }
}

#if !os(macOS)
class ImagePipelineProcessedDataCachingTests: XCTestCase {
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
            $0.isDataCacheForOriginalDataEnabled = true
            $0.isDataCacheForProcessedDataEnabled = true
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

    func testProcessedImageIsDecompressed() {
        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        expect(pipeline).toLoadImage(with: request) { result in
            guard let image = result.value?.image else {
                return XCTFail("Expected image to be loaded")
            }

            let isDecompressionNeeded = ImageDecompressor.isDecompressionNeeded(for: image)
            XCTAssertEqual(isDecompressionNeeded, false, "Expected image to be decompressed")
        }
        wait()
    }

    func testProcessedImageNotDecompressedWhenDecompressionDisabled() {
        // Given pipeline with decompression disabled
        var configuration = pipeline.configuration
        configuration.isDecompressionEnabled = false
        let pipeline = ImagePipeline(configuration: configuration)

        // Given processed image data stored in data cache
        dataLoader.queue.isSuspended = true
        dataCache.store[Test.url.absoluteString + "1"] = Test.data

        // When/Then
        expect(pipeline).toLoadImage(with: request) { result in
            guard let image = result.value?.image else {
                return XCTFail("Expected image to be loaded")
            }

            let isDecompressionNeeded = ImageDecompressor.isDecompressionNeeded(for: image)
            XCTAssertEqual(isDecompressionNeeded, true, "Expected image to still be marked as non decompressed")
        }
        wait()
    }

    func testBothProcessedAndOriginalImageDataStoredInDataCache() {
        // When
        pipeline.configuration.imageEncodingQueue.isSuspended = true
        expect(pipeline).toLoadImage(with: request)
        expect(pipeline.configuration.imageEncodingQueue).toFinishWithEnqueuedOperationCount(1)

        // Then
        wait { _ in
            XCTAssertNotNil(self.dataCache.cachedData(for: Test.url.absoluteString), "Expected original image data to be stored")
            XCTAssertNotNil(self.dataCache.cachedData(for: Test.url.absoluteString + "1"), "Expected processed image data to be stored")
            XCTAssertEqual(self.dataCache.store.count, 2)
        }
    }

    func testOriginalDataNotStoredWhenStorageDisabled() {
        // Given
        var configuration = pipeline.configuration
        configuration.isDataCacheForOriginalDataEnabled = false
        let pipeline = ImagePipeline(configuration: configuration)

        // When
        pipeline.configuration.imageEncodingQueue.isSuspended = true
        expect(pipeline).toLoadImage(with: request)
        expect(pipeline.configuration.imageEncodingQueue).toFinishWithEnqueuedOperationCount(1)

        // Then
        wait { _ in
            XCTAssertNotNil(self.dataCache.cachedData(for: Test.url.absoluteString + "1"), "Expected processed image data to be stored")
            XCTAssertEqual(self.dataCache.store.count, 1)
        }
    }

    func testProcessedDataNotStoredWhenStorageDisabled() {
        // Given
        var configuration = pipeline.configuration
        configuration.isDataCacheForProcessedDataEnabled = false
        let pipeline = ImagePipeline(configuration: configuration)

        // When
        expect(pipeline).toLoadImage(with: request)

        // Then
        wait { _ in
            XCTAssertNotNil(self.dataCache.cachedData(for: Test.url.absoluteString), "Expected original image data to be stored")
            XCTAssertEqual(self.dataCache.store.count, 1)
        }
    }

    func testSetCustomImageEncoder() {
        struct MockImageEncoder: ImageEncoding {
            let closure: (Image) -> Data?

            func encode(image: Image) -> Data? {
                return closure(image)
            }
        }

        // Given
        var configuration = pipeline.configuration
        var isCustomEncoderCalled = false
        let encoder = MockImageEncoder { _ in
            isCustomEncoderCalled = true
            return nil
        }
        configuration.makeImageEncoder = { _ in
            return encoder
        }
        let pipeline = ImagePipeline(configuration: configuration)

        // When
        pipeline.configuration.imageEncodingQueue.isSuspended = true
        expect(pipeline).toLoadImage(with: request)
        expect(pipeline.configuration.imageEncodingQueue).toFinishWithEnqueuedOperationCount(1)

        // Then
        wait { _ in
            XCTAssertTrue(isCustomEncoderCalled)
            XCTAssertNil(self.dataCache.cachedData(for: Test.url.absoluteString + "1"), "Expected processed image data to not be stored")
        }
    }
}
#endif

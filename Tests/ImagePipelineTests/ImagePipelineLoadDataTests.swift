//// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineLoadDataTests: XCTestCase {
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

    func testLoadDataDataLoaded() {
        let expectation = self.expectation(description: "Image data Loaded")
        pipeline.loadData(with: Test.request) { result in
            let response = try! XCTUnwrap(result.value)
            XCTAssertEqual(response.data.count, 22789)
            XCTAssertTrue(Thread.isMainThread)
            expectation.fulfill()
        }
        wait()
    }

    // MARK: - Progress Reporting

    func testProgressClosureIsCalled() {
        // Given
        let request = ImageRequest(url: Test.url)

        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let expectedProgress = expectProgress([(10, 20), (20, 20)])

        pipeline.loadData(
            with: request,
            progress: { completed, total in
                // Then
                XCTAssertTrue(Thread.isMainThread)
                expectedProgress.received((completed, total))
            },
            completion: { _ in }
        )

        wait()
    }

    func testProgressObjectIsUpdated() {
        // Given
        let request = Test.request

        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let expectTaskFinished = self.expectation(description: "Task finished")
        let task = pipeline.loadData(with: request) { _ in
            expectTaskFinished.fulfill()
        }

        // Then
        self.expect(values: [20], for: task.progress, keyPath: \.totalUnitCount) { _, _ in
            XCTAssertTrue(Thread.isMainThread)
        }
        self.expect(values: [10, 20], for: task.progress, keyPath: \.completedUnitCount) { _, _ in
            XCTAssertTrue(Thread.isMainThread)
        }

        wait()
    }

    func testTaskProgressIsUpdated() {
        // Given
        let request = ImageRequest(url: Test.url)

        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let expectedProgress = expectProgress([(10, 20), (20, 20)])

        var task: ImageTask!
        task = pipeline.loadData(
            with: request,
            progress: { completed, total in
                // Then
                XCTAssertTrue(Thread.isMainThread)
                expectedProgress.received((task.completedUnitCount, task.totalUnitCount))
            },
            completion: { _ in }
        )

        wait()
    }

    // MARK: - Callback Queues

    func testChangingCallbackQueueLoadData() {
        // GIVEN
        let queue = DispatchQueue(label: "testChangingCallbackQueue")
        let queueKey = DispatchSpecificKey<Void>()
        queue.setSpecific(key: queueKey, value: ())

        // WHEN/THEN
        let expectation = self.expectation(description: "Image data Loaded")
        pipeline.loadData(with: Test.request,queue: queue, progress: { _, _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
        }, completion: { _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
            expectation.fulfill()
        })
        wait()
    }

    // MARK: - Errors

    func testLoadWithInvalidURL() throws {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataLoader = DataLoader()
        }

        // WHEN
        let record = expect(pipeline).toLoadData(with: "http://example.com/invalid url")
        wait()

        // THEN
        let result = try XCTUnwrap(record.result)
        XCTAssertTrue(result.isFailure)
    }
}

// MARK: - ImagePipelineLoadDataTests (ImageRequest.CachePolicy)

extension ImagePipelineLoadDataTests {
    func testCacheLookupWithDefaultPolicyImageStored() {
        // GIVEN
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        let record = expect(pipeline).toLoadData(with: Test.request)
        wait()

        // THEN
        XCTAssertEqual(dataCache.readCount, 1)
        XCTAssertEqual(dataCache.writeCount, 1) // Initial write
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
        XCTAssertNotNil(record.data)
    }

    func testCacheLookupWithReloadPolicyImageStored() {
        // GIVEN
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        let request = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
        let record = expect(pipeline).toLoadData(with: request)
        wait()

        // THEN
        XCTAssertEqual(dataCache.readCount, 0)
        XCTAssertEqual(dataCache.writeCount, 2) // Initial write + write after fetch
        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(record.data)
    }
}

// MARK: - ImagePipelineLoadDataTests (DataCachePolicy)

extension ImagePipelineLoadDataTests {
    // MARK: DataCachPolicy.automatic

    func testPolicyAutomaticGivenRequestWithProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        expect(pipeline).toLoadData(with: request)
        wait()

        // THEN nothing is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataCache.store.count, 0)
    }

    func testPolicyAutomaticGivenRequestWithoutProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        expect(pipeline).toLoadData(with: request)
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
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
        }
        wait()

        // THEN
        // only original image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
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
        expect(pipeline).toLoadData(with: request)
        wait()

        // THEN nothing is stored in disk cache
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
        expect(pipeline).toLoadData(with: request)
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
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
        }
        wait()

        // THEN
        // only original image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
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
        expect(pipeline).toLoadData(with: request)
        wait()

        // THEN nothing is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataCache.store.count, 0)
    }

    func testPolicyStoreEncodedImagesGivenRequestWithoutProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        expect(pipeline).toLoadData(with: request)
        wait()

        // THEN original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataCache.store.count, 0)
    }

    func testPolicyStoreEncodedImagesGivenTwoRequests() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // WHEN
        expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
        wait()

        // THEN
        // only original image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataCache.store.count, 0)
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
        expect(pipeline).toLoadData(with: request)
        wait()

        // THEN nothing is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicyStoreAllGivenRequestWithoutProcessors() {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        expect(pipeline).toLoadData(with: request)
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
        pipeline.resgiterMultipleRequests {
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
        }
        wait()

        // THEN
        // only original image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }
}

extension ImagePipeline {
    func resgiterMultipleRequests(_ closure: () -> Void) {
        configuration.dataLoadingQueue.isSuspended = true
        closure()
        queue.sync {} // Important!
        configuration.dataLoadingQueue.isSuspended = false
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

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
        let encoder = MockImageEncoder(result: Test.data)
        self.encoder = encoder

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.makeImageEncoder = { _ in encoder }
            // TODO: rework
//            $0.debugIsSyncImageEncoding = true
        }
    }

    func testLoadDataDataLoaded() {
        let expectation = self.expectation(description: "Image data Loaded")
        pipeline.loadData(with: Test.request) { result in
            guard let response = result.value else {
                return XCTFail()
            }
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

    func testTaskProgressIsUpdated() {
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

    // MARK: - Errors

    func testLoadWithInvalidURL() throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataLoader = DataLoader()
        }

        // When
        let record = expect(pipeline).toLoadData(with: ImageRequest(url: URL(string: "")))
        wait()

        // Then
        let result = try XCTUnwrap(record.result)
        XCTAssertTrue(result.isFailure)
    }
}

// MARK: - ImagePipelineLoadDataTests (ImageRequest.CachePolicy)

extension ImagePipelineLoadDataTests {
    func testCacheLookupWithDefaultPolicyImageStored() {
        // Given
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // When
        let record = expect(pipeline).toLoadData(with: Test.request)
        wait()

        // Then
        XCTAssertEqual(dataCache.readCount, 1)
        XCTAssertEqual(dataCache.writeCount, 1) // Initial write
        XCTAssertEqual(dataLoader.createdTaskCount, 0)
        XCTAssertNotNil(record.data)
    }

    func testCacheLookupWithReloadPolicyImageStored() {
        // Given
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // When
        let request = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
        let record = expect(pipeline).toLoadData(with: request)
        wait()

        // Then
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
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        expect(pipeline).toLoadData(with: request)
        wait()

        // Then nothing is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataCache.store.count, 0)
    }

    func testPolicyAutomaticGivenRequestWithoutProcessors() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        expect(pipeline).toLoadData(with: request)
        wait()

        // Then original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicyAutomaticGivenTwoRequests() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // When
        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
        }
        wait()

        // Then
        // only original image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    // MARK: DataCachPolicy.storeOriginalData

    func testPolicystoreOriginalDataGivenRequestWithProcessors() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        expect(pipeline).toLoadData(with: request)
        wait()

        // Then nothing is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicystoreOriginalDataGivenRequestWithoutProcessors() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        expect(pipeline).toLoadData(with: request)
        wait()

        // Then original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicystoreOriginalDataGivenTwoRequests() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // When
        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
        }
        wait()

        // Then
        // only original image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    // MARK: DataCachPolicy.storeEncodedImages

    func testPolicyStoreEncodedImagesGivenRequestWithProcessors() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        expect(pipeline).toLoadData(with: request)
        wait()

        // Then nothing is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataCache.store.count, 0)
    }

    func testPolicyStoreEncodedImagesGivenRequestWithoutProcessors() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        expect(pipeline).toLoadData(with: request)
        wait()

        // Then original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataCache.store.count, 0)
    }

    func testPolicyStoreEncodedImagesGivenTwoRequests() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // When
        expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
        wait()

        // Then
        // only original image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 0)
        XCTAssertEqual(dataCache.store.count, 0)
    }

    // MARK: DataCachPolicy.storeAll

    func testPolicyStoreAllGivenRequestWithProcessors() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        expect(pipeline).toLoadData(with: request)
        wait()

        // Then nothing is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicyStoreAllGivenRequestWithoutProcessors() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        expect(pipeline).toLoadData(with: request)
        wait()

        // Then original image data is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }

    func testPolicyStoreAllGivenTwoRequests() {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // When
        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
        }
        wait()

        // Then
        // only original image is stored in disk cache
        XCTAssertEqual(encoder.encodeCount, 0)
        XCTAssertNil(dataCache.cachedData(for: Test.url.absoluteString + "p1"))
        XCTAssertNotNil(dataCache.cachedData(for: Test.url.absoluteString))
        XCTAssertEqual(dataCache.writeCount, 1)
        XCTAssertEqual(dataCache.store.count, 1)
    }
}

extension XCTestCase {
    // TODO: remove
    func withSuspendedDataLoader(for pipeline: ImagePipeline, expectedRequestCount count: Int, _ closure: () -> Void) {
        let dataLoader = pipeline.configuration.dataLoader as! MockDataLoader
        dataLoader.isSuspended = true
        let expectation = self.expectation(description: "registered")
        expectation.expectedFulfillmentCount = count
        pipeline.onTaskStarted = { _ in
            expectation.fulfill()
        }
        closure()
        wait(for: [expectation], timeout: 5)
        dataLoader.isSuspended = false
    }
}

final class TestExpectation {

}

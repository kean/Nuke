// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite struct ImagePipelineLoadDataTests {
    var dataLoader: MockDataLoader!
    var dataCache: MockDataCache!
    var pipeline: ImagePipeline!
    var encoder: MockImageEncoder!

    init() {
        dataLoader = MockDataLoader()
        dataCache = MockDataCache()
        let encoder = MockImageEncoder(result: Test.data)
        self.encoder = encoder

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.makeImageEncoder = { _ in encoder }
            $0.debugIsSyncImageEncoding = true
        }
    }

    @Test func loadDataDataLoaded() async throws {
        // When
        let response = try await pipeline.data(for: Test.request)

        // Then
        #expect(response.data.count == 22789)
    }

    // MARK: - Progress Reporting

//    @Test func progressIsReported() async throws {
//        // Given
//        let request = ImageRequest(url: Test.url)
//
//        dataLoader.results[Test.url] = .success(
//            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
//        )
//
//        // When
//        let expectedProgress = expectProgress([(10, 20), (20, 20)])
//
//        pipeline.loadData(
//            with: request,
//            progress: { completed, total in
//                // Then
//                #expect(Thread.isMainThread)
//                expectedProgress.received((completed, total))
//            },
//            completion: { _ in }
//        )
//
//        wait()
//    }
//
//    // MARK: - Errors
//
//    @Test func loadWithInvalidURL() throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataLoader = DataLoader()
//        }
//
//        // When
//        let record = expect(pipeline).toLoadData(with: ImageRequest(url: URL(string: "")))
//        wait()
//
//        // Then
//        let result = try #require(record.result)
//        #expect(result.isFailure)
//    }
}

//// MARK: - ImagePipelineLoadDataTests (ImageRequest.CachePolicy)
//
//extension ImagePipelineLoadDataTests {
//    @Test func cacheLookupWithDefaultPolicyImageStored() async throws {
//        // Given
//        pipeline.cache.storeCachedImage(Test.container, for: Test.request)
//
//        // When
//        let record = expect(pipeline).toLoadData(with: Test.request)
//        wait()
//
//        // Then
//        #expect(dataCache.readCount == 1)
//        #expect(dataCache.writeCount == 1) // Initial write // Initial write
//        #expect(dataLoader.createdTaskCount == 0)
//        #expect(record.data != nil)
//    }
//
//    @Test func cacheLookupWithReloadPolicyImageStored() async throws {
//        // Given
//        pipeline.cache.storeCachedImage(Test.container, for: Test.request)
//
//        // When
//        let request = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
//        let record = expect(pipeline).toLoadData(with: request)
//        wait()
//
//        // Then
//        #expect(dataCache.readCount == 0)
//        #expect(dataCache.writeCount == 2) // Initial write + write after fetch // Initial write + write after fetch
//        #expect(dataLoader.createdTaskCount == 1)
//        #expect(record.data != nil)
//    }
//}
//
//// MARK: - ImagePipelineLoadDataTests (DataCachePolicy)
//
//extension ImagePipelineLoadDataTests {
//    // MARK: DataCachPolicy.automatic
//
//    @Test func policyAutomaticGivenRequestWithProcessors() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//        }
//
//        // Given request with a processor
//        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
//
//        // When
//        expect(pipeline).toLoadData(with: request)
//        wait()
//
//        // Then nothing is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
//        #expect(dataCache.writeCount == 0)
//        #expect(dataCache.store.count == 0)
//    }
//
//    @Test func policyAutomaticGivenRequestWithoutProcessors() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//        }
//
//        // Given request without a processor
//        let request = ImageRequest(url: Test.url)
//
//        // When
//        expect(pipeline).toLoadData(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policyAutomaticGivenTwoRequests() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .automatic
//        }
//
//        // When
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
//            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
//        }
//        wait()
//
//        // Then
//        // only original image is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    // MARK: DataCachPolicy.storeOriginalData
//
//    @Test func policystoreOriginalDataGivenRequestWithProcessors() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeOriginalData
//        }
//
//        // Given request with a processor
//        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
//
//        // When
//        expect(pipeline).toLoadData(with: request)
//        wait()
//
//        // Then nothing is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policystoreOriginalDataGivenRequestWithoutProcessors() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeOriginalData
//        }
//
//        // Given request without a processor
//        let request = ImageRequest(url: Test.url)
//
//        // When
//        expect(pipeline).toLoadData(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policystoreOriginalDataGivenTwoRequests() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeOriginalData
//        }
//
//        // When
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
//            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
//        }
//        wait()
//
//        // Then
//        // only original image is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    // MARK: DataCachPolicy.storeEncodedImages
//
//    @Test func policyStoreEncodedImagesGivenRequestWithProcessors() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeEncodedImages
//        }
//
//        // Given request with a processor
//        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
//
//        // When
//        expect(pipeline).toLoadData(with: request)
//        wait()
//
//        // Then nothing is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
//        #expect(dataCache.writeCount == 0)
//        #expect(dataCache.store.count == 0)
//    }
//
//    @Test func policyStoreEncodedImagesGivenRequestWithoutProcessors() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeEncodedImages
//        }
//
//        // Given request without a processor
//        let request = ImageRequest(url: Test.url)
//
//        // When
//        expect(pipeline).toLoadData(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
//        #expect(dataCache.writeCount == 0)
//        #expect(dataCache.store.count == 0)
//    }
//
//    @Test func policyStoreEncodedImagesGivenTwoRequests() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeEncodedImages
//        }
//
//        // When
//        expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
//        expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
//        wait()
//
//        // Then
//        // only original image is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
//        #expect(dataCache.writeCount == 0)
//        #expect(dataCache.store.count == 0)
//    }
//
//    // MARK: DataCachPolicy.storeAll
//
//    @Test func policyStoreAllGivenRequestWithProcessors() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeAll
//        }
//
//        // Given request with a processor
//        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])
//
//        // When
//        expect(pipeline).toLoadData(with: request)
//        wait()
//
//        // Then nothing is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policyStoreAllGivenRequestWithoutProcessors() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeAll
//        }
//
//        // Given request without a processor
//        let request = ImageRequest(url: Test.url)
//
//        // When
//        expect(pipeline).toLoadData(with: request)
//        wait()
//
//        // Then original image data is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//
//    @Test func policyStoreAllGivenTwoRequests() async throws {
//        // Given
//        pipeline = pipeline.reconfigured {
//            $0.dataCachePolicy = .storeAll
//        }
//
//        // When
//        withSuspendedDataLoader(for: pipeline, expectedRequestCount: 2) {
//            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
//            expect(pipeline).toLoadData(with: ImageRequest(url: Test.url))
//        }
//        wait()
//
//        // Then
//        // only original image is stored in disk cache
//        #expect(encoder.encodeCount == 0)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
//        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
//        #expect(dataCache.writeCount == 1)
//        #expect(dataCache.store.count == 1)
//    }
//}

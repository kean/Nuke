// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@Suite class ImagePipelineLoadDataTests {
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

    // MARK: - Errors

    @Test func loadWithInvalidURL() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataLoader = DataLoader()
        }

        // When
        do {
            _ = try await pipeline.data(for: ImageRequest(url: URL(string: "")))
            Issue.record()
        } catch {
            // Then
            if case .dataLoadingFailed = error {
                // Expected
            } else {
                Issue.record()
            }
        }
    }

    // MARK: - ImageRequest.CachePolicy

    @Test func cacheLookupWithDefaultPolicyImageStored() async throws {
        // Given
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // When
        let response = try await pipeline.data(for: Test.request)

        // Then
        #expect(dataCache.readCount == 1)
        #expect(dataCache.writeCount == 1) // Initial write // Initial write
        #expect(dataLoader.createdTaskCount == 0)
        #expect(!response.data.isEmpty)
    }

    @Test func cacheLookupWithReloadPolicyImageStored() async throws {
        // Given
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // When
        let request = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
        let response = try await pipeline.data(for: request)

        // Then
        #expect(dataCache.readCount == 0)
        #expect(dataCache.writeCount == 2) // Initial write + write after fetch // Initial write + write after fetch
        #expect(dataLoader.createdTaskCount == 1)
        #expect(!response.data.isEmpty)
    }

    // MARK: - DataCachePolicy

    @Test func policyAutomaticGivenRequestWithProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        _ = try await pipeline.data(for: request)

        // Then nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func policyAutomaticGivenRequestWithoutProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        _ = try await pipeline.data(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @ImagePipelineActor // important
    @Test func policyAutomaticGivenTwoRequests() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // When
        let pipeline = pipeline!
        async let task1 = pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        async let task2 = pipeline.data(for: ImageRequest(url: Test.url))
        _ = try await (task1, task2)

        // Then only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    // MARK: DataCachPolicy.storeOriginalData

    @Test func policystoreOriginalDataGivenRequestWithProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        _ = try await pipeline.data(for: request)

        // Then nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policystoreOriginalDataGivenRequestWithoutProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        _ = try await pipeline.data(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @ImagePipelineActor
    @Test func policyStoreOriginalDataGivenTwoRequests() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // When
        // TODO: this should subscribe to a single task
        let pipeline = pipeline!
        async let task1 = pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        async let task2 = pipeline.data(for: ImageRequest(url: Test.url))
        _ =  try await (task1, task2)

        // Then
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    // MARK: DataCachPolicy.storeEncodedImages

    @Test func policyStoreEncodedImagesGivenRequestWithProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        _ = try await pipeline.data(for: request)

        // Then nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func policyStoreEncodedImagesGivenRequestWithoutProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        _ = try await pipeline.data(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @ImagePipelineActor
    @Test func policyStoreEncodedImagesGivenTwoRequests() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // When
        let pipeline = pipeline!
        async let task1 = pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        async let task2 = pipeline.data(for: ImageRequest(url: Test.url))
        _ =  try await (task1, task2)

        // Then
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    // MARK: DataCachPolicy.storeAll

    @Test func policyStoreAllGivenRequestWithProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // Given request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // When
        _ = try await pipeline.data(for: request)

        // Then nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreAllGivenRequestWithoutProcessors() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // Given request without a processor
        let request = ImageRequest(url: Test.url)

        // When
        _ = try await pipeline.data(for: request)

        // Then original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @ImagePipelineActor
    @Test func policyStoreAllGivenTwoRequests() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // When
        let pipeline = pipeline!
        async let task1 = pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        async let task2 = pipeline.data(for: ImageRequest(url: Test.url))
        _ =  try await (task1, task2)

        // Then
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }
}

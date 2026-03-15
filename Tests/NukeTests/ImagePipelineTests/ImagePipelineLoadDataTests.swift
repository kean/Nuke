// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(1)))
struct ImagePipelineLoadDataTests {
    let dataLoader: MockDataLoader
    let dataCache: MockDataCache
    let pipeline: ImagePipeline
    let encoder: MockImageEncoder

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let encoder = MockImageEncoder(result: Test.data)
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.encoder = encoder
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
            $0.makeImageEncoder = { _ in encoder }
        }
    }

    @Test func loadDataDataLoaded() async throws {
        let (data, _) = try await pipeline.data(for: Test.request)
        #expect(data.count == 22789)
    }

    // MARK: - Progress Reporting

    @Test func progressClosureIsCalled() async throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Data(count: 20), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let task = pipeline.imageTask(with: Test.url)
        var progressValues: [ImageTask.Progress] = []
        for await progress in task.progress {
            progressValues.append(progress)
        }
        _ = try? await task.response

        // Then
        #expect(progressValues == [
            ImageTask.Progress(completed: 10, total: 20),
            ImageTask.Progress(completed: 20, total: 20)
        ])
    }

    // MARK: - Errors

    @Test func loadWithInvalidURL() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataLoader = DataLoader()
        }

        // WHEN/THEN
        do {
            _ = try await pipeline.data(for: ImageRequest(url: URL(string: "")))
            Issue.record("Expected failure")
        } catch {
            // Expected
        }
    }

    @Test func downloadExceedingMaximumResponseDataSize() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.maximumResponseDataSize = 1024
        }

        // WHEN/THEN
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            guard case .dataDownloadExceededMaximumSize = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    // MARK: - ImageRequest.CachePolicy

    @Test func cacheLookupWithDefaultPolicyImageStored() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        _ = try await pipeline.data(for: Test.request)

        // THEN
        #expect(dataCache.readCount == 1)
        #expect(dataCache.writeCount == 1) // Initial write
        #expect(dataLoader.createdTaskCount == 0)
    }

    @Test func cacheLookupWithReloadPolicyImageStored() async throws {
        // GIVEN
        pipeline.cache.storeCachedImage(Test.container, for: Test.request)

        // WHEN
        let request = ImageRequest(url: Test.url, options: [.reloadIgnoringCachedData])
        _ = try await pipeline.data(for: request)

        // THEN
        #expect(dataCache.readCount == 0)
        #expect(dataCache.writeCount == 2) // Initial write + write after fetch
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - DataCachePolicy

    // MARK: DataCachPolicy.automatic

    @Test func policyAutomaticGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func policyAutomaticGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyAutomaticGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .automatic
        }

        // WHEN
        _ = try await pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.data(for: ImageRequest(url: Test.url))

        // THEN
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    // MARK: DataCachPolicy.storeOriginalData

    @Test func policyStoreOriginalDataGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreOriginalDataGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreOriginalDataGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeOriginalData
        }

        // WHEN
        _ = try await pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.data(for: ImageRequest(url: Test.url))

        // THEN
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    // MARK: DataCachPolicy.storeEncodedImages

    @Test func policyStoreEncodedImagesGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func policyStoreEncodedImagesGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    @Test func policyStoreEncodedImagesGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeEncodedImages
        }

        // WHEN
        _ = try await pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.data(for: ImageRequest(url: Test.url))

        // THEN
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) == nil)
        #expect(dataCache.writeCount == 0)
        #expect(dataCache.store.count == 0)
    }

    // MARK: DataCachPolicy.storeAll

    @Test func policyStoreAllGivenRequestWithProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // GIVEN request with a processor
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")])

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN nothing is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreAllGivenRequestWithoutProcessors() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // GIVEN request without a processor
        let request = ImageRequest(url: Test.url)

        // WHEN
        _ = try await pipeline.data(for: request)

        // THEN original image data is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }

    @Test func policyStoreAllGivenTwoRequests() async throws {
        // GIVEN
        let pipeline = pipeline.reconfigured {
            $0.dataCachePolicy = .storeAll
        }

        // WHEN
        _ = try await pipeline.data(for: ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "p1")]))
        _ = try await pipeline.data(for: ImageRequest(url: Test.url))

        // THEN
        // only original image is stored in disk cache
        #expect(encoder.encodeCount == 0)
        #expect(dataCache.cachedData(for: Test.url.absoluteString + "p1") == nil)
        #expect(dataCache.cachedData(for: Test.url.absoluteString) != nil)
        #expect(dataCache.writeCount == 1)
        #expect(dataCache.store.count == 1)
    }
}

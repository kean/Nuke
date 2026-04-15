// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDelegateTests {
    private let dataLoader: MockDataLoader
    private let dataCache: MockDataCache
    private let pipeline: ImagePipeline
    private let delegate: MockImagePipelineDelegate

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let delegate = MockImagePipelineDelegate()
        self.dataLoader = dataLoader
        self.dataCache = dataCache
        self.delegate = delegate
        self.pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.dataCachePolicy = .automatic
            $0.imageCache = nil
        }
    }

    @Test @MainActor func customizingDataCacheKey() async throws {
        // GIVEN
        let imageURLSmall = URL(string: "https://example.com/image-01-small.jpeg")!
        let imageURLMedium = URL(string: "https://example.com/image-01-medium.jpeg")!

        dataLoader.results[imageURLMedium] = .success(
            (Test.data, URLResponse(url: imageURLMedium, mimeType: "jpeg", expectedContentLength: Test.data.count, textEncodingName: nil))
        )

        // GIVEN image is loaded from medium size URL and saved in cache using imageId "image-01-small"
        let requestA = ImageRequest(
            url: imageURLMedium,
            processors: [.resize(width: 44)],
            userInfo: ["imageId": "image-01-small"]
        )
        _ = try await pipeline.image(for: requestA)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        let data = try #require(dataCache.cachedData(for: "image-01-small"))
        let image = try #require(PlatformImage(data: data))
        #expect(image.sizeInPixels.width == 44 * Screen.scale)

        // GIVEN a request for a small image
        let requestB = ImageRequest(
            url: imageURLSmall,
            userInfo: ["imageId": "image-01-small"]
        )

        // WHEN/THEN the image is returned from the disk cache
        let responseB = try await pipeline.imageTask(with: requestB).response
        #expect(responseB.image.sizeInPixels.width == 44 * Screen.scale)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func dataIsStoredInCache() async throws {
        // WHEN
        _ = try await pipeline.image(for: Test.request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(!dataCache.store.isEmpty)
    }

    @Test func dataIsStoredInCacheWhenCacheDisabled() async throws {
        // WHEN
        delegate.isCacheEnabled = false
        _ = try await pipeline.image(for: Test.request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(dataCache.store.isEmpty)
    }

    // MARK: - willLoadData

    @Test func willLoadDataIsCalled() async throws {
        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(delegate.willLoadDataCallCount == 1)
        #expect(delegate.willLoadDataRequest?.url == Test.url)
    }

    @Test func willLoadDataCanModifyRequest() async throws {
        // GIVEN
        let trackingLoader = TrackingDataLoader(wrapping: dataLoader)
        delegate.urlRequestModifier = { request in
            var request = request
            request.setValue("Bearer token123", forHTTPHeaderField: "Authorization")
            return request
        }
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = trackingLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN the data loader received the modified request
        #expect(trackingLoader.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
    }

    @Test func willLoadDataThrowingCancelsWithDataLoadingFailed() async throws {
        // GIVEN
        struct TokenRefreshError: Error {}
        delegate.willLoadDataError = TokenRefreshError()

        // WHEN
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected an error")
        } catch {
            // THEN the error is wrapped in dataLoadingFailed
            guard case .dataLoadingFailed(let underlying) = error else {
                Issue.record("Expected dataLoadingFailed, got \(error)")
                return
            }
            #expect(underlying is TokenRefreshError)
        }
    }

    @Test func willLoadDataIsNotCalledForCustomDataFetch() async throws {
        // GIVEN a request using a custom data fetch closure
        let request = ImageRequest(id: "test", data: {
            Test.data
        })

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN willLoadData is NOT called (custom fetch bypasses URL loading)
        #expect(delegate.willLoadDataCallCount == 0)
    }
}

private final class MockImagePipelineDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    var isCacheEnabled = true

    // willLoadData tracking
    var willLoadDataCallCount = 0
    var willLoadDataRequest: URLRequest?
    var urlRequestModifier: ((URLRequest) -> URLRequest)?
    var willLoadDataError: Error?

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        request.userInfo["imageId"] as? String
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void) {
        completion(isCacheEnabled ? data : nil)
    }

    func willLoadData(
        for request: ImageRequest,
        urlRequest: URLRequest,
        pipeline: ImagePipeline
    ) async throws -> URLRequest {
        willLoadDataCallCount += 1
        willLoadDataRequest = urlRequest
        if let error = willLoadDataError { throw error }
        return urlRequestModifier?(urlRequest) ?? urlRequest
    }
}

private final class TrackingDataLoader: DataLoading, @unchecked Sendable {
    private let wrapped: MockDataLoader
    var lastRequest: URLRequest?

    init(wrapping loader: MockDataLoader) {
        self.wrapped = loader
    }

    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        lastRequest = request
        return wrapped.loadData(with: request, didReceiveData: didReceiveData, completion: completion)
    }
}

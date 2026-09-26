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
    private let delegate: MockCachingDelegate

    init() {
        let dataLoader = MockDataLoader()
        let dataCache = MockDataCache()
        let delegate = MockCachingDelegate()
        delegate.cacheKey = { $0.userInfo["imageId"] as? String }
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
        var requestA = ImageRequest(
            url: imageURLMedium,
            processors: [.resize(width: 44)]
        )
        requestA.userInfo = ["imageId": "image-01-small"]
        _ = try await pipeline.image(for: requestA)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        let data = try #require(dataCache.cachedData(for: "image-01-small"))
        let image = try #require(PlatformImage(data: data))
        #expect(image.sizeInPixels.width == 44 * Screen.scale)

        // GIVEN a request for a small image
        var requestB = ImageRequest(url: imageURLSmall)
        requestB.userInfo = ["imageId": "image-01-small"]

        // WHEN/THEN the image is returned from the disk cache
        let responseB = try await pipeline.imageTask(with: requestB).response
        #expect(responseB.image.sizeInPixels.width == 44 * Screen.scale)
        #expect(dataLoader.createdTaskCount == 1)
    }

    // MARK: - willCache

    @Test func dataIsStoredInCache() async throws {
        // WHEN
        _ = try await pipeline.image(for: Test.request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(!dataCache.store.isEmpty)
    }

    @Test func dataIsStoredInCacheWhenCacheDisabled() async throws {
        // WHEN
        delegate.willCacheTransform = { _ in nil }
        _ = try await pipeline.image(for: Test.request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN
        #expect(dataCache.store.isEmpty)
    }

    @Test func willCacheReturningNilPreventsStoringData() async throws {
        // GIVEN a delegate that returns `nil` from `willCache`
        delegate.willCacheTransform = { _ in nil }

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN nothing is written to the disk cache
        #expect(dataCache.store.isEmpty)
        #expect(dataCache.writeCount == 0)
    }

    @Test func willCacheReturningEmptyDataPreventsStoringData() async throws {
        // GIVEN a delegate that returns empty data from `willCache`
        delegate.willCacheTransform = { _ in Data() }

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN nothing is written to the disk cache
        #expect(dataCache.store.isEmpty)
        #expect(dataCache.writeCount == 0)
    }

    @Test func willCacheReturningEmptyDataPreventsStoringEncodedImage() async throws {
        // GIVEN a delegate that returns empty data from `willCache` and a request
        // that makes the pipeline store a processed (re-encoded) image
        delegate.willCacheTransform = { _ in Data() }
        let request = ImageRequest(url: Test.url, processors: [.resize(width: 44)])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN nothing is written to the disk cache
        #expect(dataCache.store.isEmpty)
        #expect(dataCache.writeCount == 0)
    }

    @Test func willCacheReturningModifiedDataStoresModifiedData() async throws {
        // GIVEN a delegate that replaces the data passed to `willCache`
        let modifiedData = Data("modified".utf8)
        delegate.willCacheTransform = { _ in modifiedData }

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN the modified data is what ends up in the disk cache
        #expect(dataCache.store.count == 1)
        #expect(dataCache.store.values.first == modifiedData)
    }

    @Test func willCacheReturningNilPreventsStoringEncodedImage() async throws {
        // GIVEN a delegate that returns `nil` from `willCache` and a request
        // that makes the pipeline store a processed (re-encoded) image
        delegate.willCacheTransform = { _ in nil }
        let request = ImageRequest(url: Test.url, processors: [.resize(width: 44)])

        // WHEN
        _ = try await pipeline.image(for: request)
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        // THEN nothing is written to the disk cache
        #expect(dataCache.store.isEmpty)
        #expect(dataCache.writeCount == 0)
    }

    // MARK: - willLoadData

    @Test func willLoadDataIsCalled() async throws {
        // GIVEN
        let delegate = MockWillLoadDataDelegate()
        let pipeline = pipeline.reconfigured(delegate: delegate)

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN
        #expect(delegate.requests.map(\.url) == [Test.url])
    }

    @Test func willLoadDataCanModifyRequest() async throws {
        // GIVEN
        let delegate = MockWillLoadDataDelegate { request in
            var request = request
            request.setValue("Bearer token123", forHTTPHeaderField: "Authorization")
            return request
        }
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.dataCache = dataCache
            $0.imageCache = nil
        }

        // WHEN
        _ = try await pipeline.image(for: Test.request)

        // THEN the data loader received the modified request
        #expect(dataLoader.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
    }

    @Test func willLoadDataThrowingCancelsWithDataLoadingFailed() async throws {
        // GIVEN
        struct TokenRefreshError: Error {}
        let pipeline = pipeline.reconfigured(delegate: MockWillLoadDataDelegate { _ in
            throw TokenRefreshError()
        })

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

    @Test(arguments: [false, true])
    func cancellationDuringWillLoadDataPreventsDataLoading(skipDataLoadingQueue: Bool) async throws {
        // GIVEN a delegate that suspends inside `willLoadData`
        let entered = AsyncGate(), proceed = AsyncGate()
        let pipeline = pipeline.reconfigured(delegate: MockWillLoadDataDelegate { request in
            entered.open()
            await proceed.wait()
            return request
        })

        var request = Test.request
        if skipDataLoadingQueue {
            request.options.insert(.skipDataLoadingQueue)
        }

        // WHEN the task is cancelled while `willLoadData` is suspended
        let task = pipeline.imageTask(with: request)
        let response = Task { try await task.response }
        await entered.wait()
        task.cancel()
        await drainPipeline()
        proceed.open()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await response.value
        }
        await drainPipeline()

        // THEN the data loading never starts and the queue slot is released
        #expect(dataLoader.createdTaskCount == 0)
        #expect(await pipeline.configuration.dataLoadingQueue.operationCount == 0)
    }

    /// The delegate runs in the task that loads the data, which is cancelled
    /// along with the request, so a delegate that supports cancellation (for
    /// example, one that refreshes a token) stops early.
    @Test(arguments: [false, true])
    func willLoadDataSeesTheTaskCancellation(skipDataLoadingQueue: Bool) async throws {
        // GIVEN a delegate that suspends inside `willLoadData` until it is cancelled
        let entered = TestExpectation()
        let cancelled = TestExpectation()
        let gate = AsyncGate()
        defer { gate.open() }
        let delegate = MockWillLoadDataDelegate { urlRequest in
            await withTaskCancellationHandler {
                entered.fulfill()
                await gate.wait()
            } onCancel: {
                cancelled.fulfill()
                gate.open()
            }
            return urlRequest
        }
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        var request = Test.request
        if skipDataLoadingQueue {
            request.options.insert(.skipDataLoadingQueue)
        }

        // WHEN
        let task = pipeline.imageTask(with: request)
        await entered.wait()
        task.cancel()

        // THEN
        await cancelled.wait()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
    }

    @Test func willLoadDataIsNotCalledForCustomDataFetch() async throws {
        // GIVEN a request using a custom data fetch closure
        let delegate = MockWillLoadDataDelegate()
        let pipeline = pipeline.reconfigured(delegate: delegate)
        let request = ImageRequest(id: "test", data: {
            Test.data
        })

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN willLoadData is NOT called (custom fetch bypasses URL loading)
        #expect(delegate.requests.isEmpty)
    }
}

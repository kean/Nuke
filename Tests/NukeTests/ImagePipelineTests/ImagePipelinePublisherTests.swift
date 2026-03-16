// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(2)))
struct ImagePipelinePublisherTests {
    let dataLoader: MockDataLoader
    let imageCache: MockImageCache
    let dataCache: MockDataCache
    let observer: ImagePipelineObserver
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let dataCache = MockDataCache()
        let observer = ImagePipelineObserver()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.dataCache = dataCache
        self.observer = observer
        self.pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
    }

    @Test func loadWithPublisher() async throws {
        // GIVEN
        let request = ImageRequest(id: "a", data: { Test.data })

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func loadWithPublisherAndApplyProcessor() async throws {
        // GIVEN
        var request = ImageRequest(id: "a", data: { Test.data })
        request.processors = [MockImageProcessor(id: "1")]

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
        #expect(response.image.nk_test_processorIDs == ["1"])
    }

    @Test func imageRequestWithPublisher() {
        // GIVEN
        let request = ImageRequest(id: "a", data: { Test.data })

        // THEN
        #expect(request.urlRequest == nil)
        #expect(request.url == nil)
    }

    @Test func cancellation() async {
        // GIVEN
        dataLoader.isSuspended = true

        // WHEN
        let cancellable = pipeline
            .imagePublisher(with: Test.request)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })

        await notification(ImagePipelineObserver.didCancelTask, object: observer) {
            cancellable.cancel()
        }
    }

    @Test func dataIsStoredInDataCache() async throws {
        // GIVEN
        let request = ImageRequest(id: "a", data: { Test.data })

        // WHEN
        _ = try await pipeline.image(for: request)

        // THEN
        #expect(!dataCache.store.isEmpty)
    }

    @Test func initWithURL() {
        _ = pipeline.imagePublisher(with: URL(string: "https://example.com/image.jpeg")!)
    }

    @Test func initWithImageRequest() {
        _ = pipeline.imagePublisher(with: ImageRequest(url: URL(string: "https://example.com/image.jpeg")))
    }
}

@Suite(.timeLimit(.minutes(2)))
struct ImagePipelinePublisherProgressiveDecodingTests {
    private let dataLoader: MockProgressiveDataLoader
    private let imageCache: MockImageCache
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockProgressiveDataLoader()
        let imageCache = MockImageCache()

        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.isResumableDataEnabled = false
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.isStoringPreviewsInMemoryCache = true
        }
    }

    @Test func imagePreviewsAreDelivered() async {
        let expectation = TestExpectation()
        nonisolated(unsafe) var previewsCount = 0
        nonisolated(unsafe) var isCompleted = false

        // WHEN
        let publisher = pipeline.imagePublisher(with: Test.url)
        let cancellable = publisher.sink(receiveCompletion: { completion in
            switch completion {
            case .failure:
                Issue.record("Unexpected failure")
            case .finished:
                isCompleted = true
                expectation.fulfill()
            }
        }, receiveValue: { response in
            previewsCount += 1
            if previewsCount == 3 {
                #expect(!response.container.isPreview)
            } else {
                #expect(response.container.isPreview)
            }
            self.dataLoader.resume()
        })
        await expectation.wait()
        withExtendedLifetime(cancellable) {}

        #expect(previewsCount == 3) // 2 partial + 1 final
        #expect(isCompleted)
    }

    @Test func imagePreviewsAreDeliveredFromMemoryCacheSynchronously() async {
        // GIVEN
        pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        let expectation = TestExpectation()
        nonisolated(unsafe) var previewsCount = 0
        nonisolated(unsafe) var isFirstPreviewProduced = false

        // WHEN
        let publisher = pipeline.imagePublisher(with: Test.url)
        let cancellable = publisher.sink(receiveCompletion: { completion in
            switch completion {
            case .failure:
                Issue.record("Unexpected failure")
            case .finished:
                expectation.fulfill()
            }
        }, receiveValue: { response in
            previewsCount += 1
            if previewsCount == 5 {
                #expect(!response.container.isPreview)
            } else {
                #expect(response.container.isPreview)
                if previewsCount >= 3 {
                    self.dataLoader.resume()
                } else {
                    isFirstPreviewProduced = true
                }
            }
        })
        #expect(isFirstPreviewProduced)
        await expectation.wait()
        withExtendedLifetime(cancellable) {}
    }
}

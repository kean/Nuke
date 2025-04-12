// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
import Combine

@testable import Nuke

@MainActor
@Suite struct ImagePipelinePublisherTests {
    var dataLoader: MockDataLoader!
    var imageCache: MockImageCache!
    var dataCache: MockDataCache!
    var observer: ImagePipelineObserver!
    var pipeline: ImagePipeline!

    init() {
        dataLoader = MockDataLoader()
        imageCache = MockImageCache()
        dataCache = MockDataCache()
        observer = ImagePipelineObserver()
        pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
    }

    @Test func cancellation() async {
        // Given
        dataLoader.isSuspended = true

        // When
        let cancellable = pipeline
            .imagePublisher(with: Test.request)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })

        let expectation = AsyncExpectation(notification: ImagePipelineObserver.didCancelTask, object: observer)
        cancellable.cancel()

        // Then
        await expectation.wait()
    }

    @Test func initWithURL() {
        _ = pipeline.imagePublisher(with: URL(string: "https://example.com/image.jpeg")!)
    }

    @Test func initWithImageRequest() {
        _ = pipeline.imagePublisher(with: ImageRequest(url: URL(string: "https://example.com/image.jpeg")))
    }
}

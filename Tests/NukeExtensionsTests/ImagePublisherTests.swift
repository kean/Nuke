// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Combine

@testable import Nuke

@Suite class ImagePublisherTests {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var cancellable: AnyCancellable?

    init() {
        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: Common Use Cases

    @Test func lowDataMode() async throws {
        // Given
        let highQualityImageURL = URL(string: "https://example.com/high-quality-image.jpeg")!
        let lowQualityImageURL = URL(string: "https://example.com/low-quality-image.jpeg")!

        dataLoader.results[highQualityImageURL] = .failure(URLError(networkUnavailableReason: .constrained) as NSError)
        dataLoader.results[lowQualityImageURL] = .success((Test.data, Test.urlResponse))

        // When
        let pipeline = self.pipeline!

        // Create the default request to fetch the high quality image.
        var urlRequest = URLRequest(url: highQualityImageURL)
        urlRequest.allowsConstrainedNetworkAccess = false
        let request = ImageRequest(urlRequest: urlRequest)

        // When
        let publisher = pipeline.imagePublisher(with: request).tryCatch { error -> AnyPublisher<ImageResponse, ImageTask.Error> in
            guard (error.dataLoadingError as? URLError)?.networkUnavailableReason == .constrained else {
                throw error
            }
            return pipeline.imagePublisher(with: lowQualityImageURL)
        }

        try await withUnsafeThrowingContinuation { continuation in
            cancellable = publisher.sink(receiveCompletion: { result in
                switch result {
                case .finished:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }, receiveValue: {
                #expect($0.image != nil)
            })
        }
    }

    // MARK: Basics

    @Test func syncCacheLookup() {
        // Given
        let cache = MockImageCache()
        cache[Test.request] = ImageContainer(image: Test.image)
        pipeline = pipeline.reconfigured {
            $0.imageCache = cache
        }

        // When
        var image: PlatformImage?
        cancellable = pipeline.imagePublisher(with: Test.url).sink(receiveCompletion: { result in
            switch result {
            case .finished:
                break // Expected result
            case .failure:
                Issue.record()
            }
        }, receiveValue: {
            image = $0.image
        })

        // Then image returned synchronously
        #expect(image != nil)
    }

    @Test func cancellation() async {
        dataLoader.queue.isSuspended = true

        let expectation1 = AsyncExpectation(notification: MockDataLoader.DidStartTask, object: dataLoader)
        let cancellable = pipeline.imagePublisher(with: Test.url).sink(receiveCompletion: { _ in }, receiveValue: { _ in })
        await expectation1.wait() // Wait till operation is created

        let expectation2 = AsyncExpectation(notification: MockDataLoader.DidCancelTask, object: dataLoader)
        cancellable.cancel()
        await expectation2.wait()
    }
}

/// We have to mock it because there is no way to construct native `URLError`
/// with a `networkUnavailableReason`.
private struct URLError: Swift.Error {
    var networkUnavailableReason: NetworkUnavailableReason?

    enum NetworkUnavailableReason {
        case cellular
        case expensive
        case constrained
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke
import Combine
import Foundation

@Suite struct ImagePublisherTests {
    private let dataLoader: MockDataLoader
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: Common Use Cases

    @Test func lowDataMode() async {
        // GIVEN
        let highQualityImageURL = URL(string: "https://example.com/high-quality-image.jpeg")!
        let lowQualityImageURL = URL(string: "https://example.com/low-quality-image.jpeg")!

        dataLoader.results[highQualityImageURL] = .failure(URLError(networkUnavailableReason: .constrained) as NSError)
        dataLoader.results[lowQualityImageURL] = .success((Test.data, Test.urlResponse))

        // WHEN
        let pipeline = self.pipeline

        // Create the default request to fetch the high quality image.
        var urlRequest = Foundation.URLRequest(url: highQualityImageURL)
        urlRequest.allowsConstrainedNetworkAccess = false
        let request = ImageRequest(urlRequest: urlRequest)

        // WHEN
        let publisher = pipeline.imagePublisher(with: request).tryCatch { error -> AnyPublisher<ImageResponse, ImagePipeline.Error> in
            guard (error.dataLoadingError as? URLError)?.networkUnavailableReason == .constrained else {
                throw error
            }
            return pipeline.imagePublisher(with: lowQualityImageURL)
        }

        var cancellable: AnyCancellable?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cancellable = publisher.sink(receiveCompletion: { result in
                switch result {
                case .finished:
                    break // Expected result
                case .failure:
                    Issue.record("Expected success")
                }
            }, receiveValue: {
                #expect($0.image != nil)
                continuation.resume()
            })
        }
        _ = cancellable
    }

    // MARK: Basics

    @Test func syncCacheLookup() {
        // GIVEN
        let cache = MockImageCache()
        cache[Test.request] = ImageContainer(image: Test.image)
        let pipeline = pipeline.reconfigured {
            $0.imageCache = cache
        }

        // WHEN
        var image: PlatformImage?
        let cancellable = pipeline.imagePublisher(with: Test.url).sink(receiveCompletion: { result in
            switch result {
            case .finished:
                break // Expected result
            case .failure:
                Issue.record("Expected success")
            }
        }, receiveValue: {
            image = $0.image
        })
        _ = cancellable

        // THEN image returned synchronously
        #expect(image != nil)
    }

    @Test func cancellation() async {
        dataLoader.queue.isSuspended = true

        var cancellable: AnyCancellable?

        // Wait for start notification
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(forName: MockDataLoader.DidStartTask, object: dataLoader, queue: nil) { _ in
                if let observer { NotificationCenter.default.removeObserver(observer) }
                continuation.resume()
            }
            cancellable = pipeline.imagePublisher(with: Test.url).sink(receiveCompletion: { _ in }, receiveValue: { _ in })
        }

        // Wait for cancel notification
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(forName: MockDataLoader.DidCancelTask, object: dataLoader, queue: nil) { _ in
                if let observer { NotificationCenter.default.removeObserver(observer) }
                continuation.resume()
            }
            cancellable?.cancel()
        }
        _ = cancellable
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

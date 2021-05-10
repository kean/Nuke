// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke
import Combine

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
class ImagePublisherTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var cancellable: AnyCancellable?

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: Common Use Cases

    func testLowDataMode() {
        // GIVEN
        let highQualityImageURL = URL(string: "https://example.com/high-quality-image.jpeg")!
        let lowQualityImageURL = URL(string: "https://example.com/low-quality-image.jpeg")!

        dataLoader.results[highQualityImageURL] = .failure(URLError(networkUnavailableReason: .constrained) as NSError)
        dataLoader.results[lowQualityImageURL] = .success((Test.data, Test.urlResponse))

        // WHEN
        let pipeline = self.pipeline!

        // Create the default request to fetch the high quality image.
        var urlRequest = URLRequest(url: highQualityImageURL)
        urlRequest.allowsConstrainedNetworkAccess = false
        let request = ImageRequest(urlRequest: urlRequest)

        // WHEN
        let publisher = pipeline.imagePublisher(with: request).tryCatch { error -> ImagePublisher in
            guard (error.dataLoadingError as? URLError)?.networkUnavailableReason == .constrained else {
                throw error
            }
            return pipeline.imagePublisher(with: lowQualityImageURL)
        }

        let expectation = self.expectation(description: "LowDataImageFetched")
        cancellable = publisher.sink(receiveCompletion: { result in
            switch result {
            case .finished:
                break // Expected result
            case .failure:
                XCTFail()
            }
        }, receiveValue: {
            XCTAssertNotNil($0.image)
            expectation.fulfill()
        })
        wait()
    }

    // MARK: Basics

    func testSyncCacheLookup() {
        // GIVEN
        let cache = MockImageCache()
        cache[Test.request] = ImageContainer(image: Test.image)
        pipeline = pipeline.reconfigured {
            $0.imageCache = cache
        }

        // WHEN
        var image: PlatformImage?
        cancellable = pipeline.imagePublisher(with: Test.url).sink(receiveCompletion: { result in
            switch result {
            case .finished:
                break // Expected result
            case .failure:
                XCTFail()
            }
        }, receiveValue: {
            image = $0.image
        })

        // THEN image returned synchronously
        XCTAssertNotNil(image)
    }

    func testCancellation() {
        dataLoader.queue.isSuspended = true

        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
        let cancellable = pipeline.imagePublisher(with: Test.url).sink(receiveCompletion: { _ in }, receiveValue: { _ in })
        wait() // Wait till operation is created

        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
        cancellable.cancel()
        wait()
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

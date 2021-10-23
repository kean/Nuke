// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if swift(>=5.5)
@available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
class ImagePipelineAsyncAwaitTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: Common Use Cases

    func testLowDataMode() async throws {
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
        func loadImage() async throws -> ImageResponse {
            do {
                return try await pipeline.loadImage(with: request)
            } catch {
                guard (error as? URLError)?.networkUnavailableReason == .constrained else {
                    throw error
                }
                return try await pipeline.loadImage(with: lowQualityImageURL)
            }
        }
        
        let response = try await loadImage()
        XCTAssertNotNil(response.image)
    }

//    // MARK: Basics
//
//    func testSyncCacheLookup() {
//        // GIVEN
//        let cache = MockImageCache()
//        cache[Test.request] = ImageContainer(image: Test.image)
//        pipeline = pipeline.reconfigured {
//            $0.imageCache = cache
//        }
//
//        // WHEN
//        var image: PlatformImage?
//        cancellable = pipeline.imagePublisher(with: Test.url).sink(receiveCompletion: { result in
//            switch result {
//            case .finished:
//                break // Expected result
//            case .failure:
//                XCTFail()
//            }
//        }, receiveValue: {
//            image = $0.image
//        })
//
//        // THEN image returned synchronously
//        XCTAssertNotNil(image)
//    }
//
//    func testCancellation() {
//        dataLoader.queue.isSuspended = true
//
//        expectNotification(MockDataLoader.DidStartTask, object: dataLoader)
//        let cancellable = pipeline.imagePublisher(with: Test.url).sink(receiveCompletion: { _ in }, receiveValue: { _ in })
//        wait() // Wait till operation is created
//
//        expectNotification(MockDataLoader.DidCancelTask, object: dataLoader)
//        cancellable.cancel()
//        wait()
//    }
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
#endif

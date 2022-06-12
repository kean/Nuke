// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

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
        @Sendable func loadImage() async throws -> ImageResponse {
            do {
                return try await pipeline.image(for: request)
            } catch {
                guard let error = (error as? ImagePipeline.Error),
                      (error.dataLoadingError as? URLError)?.networkUnavailableReason == .constrained else {
                    throw error
                }
                return try await pipeline.image(for: lowQualityImageURL)
            }
        }

        let response = try await loadImage()
        XCTAssertNotNil(response.image)
    }

    private var observer: AnyObject?
    
    func testCancellation() async throws {
        dataLoader.queue.isSuspended = true

        let task = _Concurrency.Task {
            try await pipeline.image(for: Test.url)
        }
        
        observer = NotificationCenter.default.addObserver(forName: MockDataLoader.DidStartTask, object: dataLoader, queue: OperationQueue()) { _ in
            task.cancel()
        }

        var caughtError: Error?
        do {
            let _ = try await task.value
        } catch {
            caughtError = error
        }
        XCTAssertTrue(caughtError is CancellationError)
    }

    func testLoadData() async throws {
        // GIVEN
        dataLoader.results[Test.url] = .success((Test.data, Test.urlResponse))

        // WHEN
        let (data, response) = try await pipeline.data(for: Test.request)

        // THEN
        XCTAssertEqual(data.count, 22788)
        XCTAssertNotNil(response?.url, Test.url.absoluteString)
    }

    // MARK: - ImageRequest with Async/Await

    func testImageRequestWithAsyncAwaitSuccess() async throws {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *) {
            // GIVEN
            let localURL = Test.url(forResource: "fixture", extension: "jpeg")

            // WHEN
            let request = ImageRequest(id: "test", data: {
                let (data, _) = try await URLSession.shared.data(for: URLRequest(url: localURL))
                return data
            })

            let container = try await pipeline.image(for: request)

            // THEN
            XCTAssertEqual(container.image.sizeInPixels, CGSize(width: 640, height: 480))
        }
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

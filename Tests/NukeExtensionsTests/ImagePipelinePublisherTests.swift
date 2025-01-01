// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import XCTest
import Combine
@testable import Nuke

class ImagePipelinePublisherTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var imageCache: MockImageCache!
    var dataCache: MockDataCache!
    var observer: ImagePipelineObserver!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

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

    func testCancellation() {
        // GIVEN
        dataLoader.isSuspended = true

        // WHEN
        let cancellable = pipeline
            .imagePublisher(with: Test.request)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
        expectNotification(ImagePipelineObserver.didCancelTask, object: observer)
        cancellable.cancel()
        wait()
    }

    func testInitWithURL() {
        _ = pipeline.imagePublisher(with: URL(string: "https://example.com/image.jpeg")!)
    }

    func testInitWithImageRequest() {
        _ = pipeline.imagePublisher(with: ImageRequest(url: URL(string: "https://example.com/image.jpeg")))
    }
}

class ImagePipelinePublisherProgressiveDecodingTests: XCTestCase {
    private var dataLoader: MockProgressiveDataLoader!
    private var imageCache: MockImageCache!
    private var pipeline: ImagePipeline!
    private var cancellable: AnyCancellable?

    override func setUp() {
        super.setUp()

        dataLoader = MockProgressiveDataLoader()
        imageCache = MockImageCache()
        ResumableDataStorage.shared.removeAllResponses()

        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.isResumableDataEnabled = false
            $0.isProgressiveDecodingEnabled = true
            $0.isStoringPreviewsInMemoryCache = true
        }
    }

    func testImagePreviewsAreDelivered() {
        let imagesProduced = self.expectation(description: "ImagesProduced")
        imagesProduced.expectedFulfillmentCount = 3 // 2 partial, 1 final
        var previewsCount = 0
        let completed = self.expectation(description: "Completed")

        // WHEN
        let publisher = pipeline.imagePublisher(with: Test.url)
        cancellable = publisher.sink(receiveCompletion: { completion in
            switch completion {
            case .failure:
                XCTFail()
            case .finished:
                completed.fulfill()
            }

        }, receiveValue: { response in
            imagesProduced.fulfill()
            if previewsCount == 2 {
                XCTAssertFalse(response.container.isPreview)
            } else {
                XCTAssertTrue(response.container.isPreview)
                previewsCount += 1
            }
            self.dataLoader.resume()
        })
        wait()
    }

    func testImagePreviewsAreDeliveredFromMemoryCacheSynchronously() {
        // GIVEN
        pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)

        let imagesProduced = self.expectation(description: "ImagesProduced")
        // 1 preview from sync cache lookup
        // 1 preview from async cache lookup (we don't want it really though)
        // 2 previews from data loading
        // 1 final image
        // we also expect resumable data to kick in for real downloads
        imagesProduced.expectedFulfillmentCount = 5
        var previewsCount = 0
        var isFirstPreviewProduced = false
        let completed = self.expectation(description: "Completed")

        // WHEN
        let publisher = pipeline.imagePublisher(with: Test.url)
        cancellable =  publisher.sink(receiveCompletion: { completion in
            switch completion {
            case .failure:
                XCTFail()
            case .finished:
                completed.fulfill()
            }

        }, receiveValue: { response in
            imagesProduced.fulfill()
            previewsCount += 1
            if previewsCount == 5 {
                XCTAssertFalse(response.container.isPreview)
            } else {
                XCTAssertTrue(response.container.isPreview)
                if previewsCount >= 3 {
                    self.dataLoader.resume()
                } else {
                    isFirstPreviewProduced = true
                }
            }
        })
        XCTAssertTrue(isFirstPreviewProduced)
        wait(200, handler: nil)
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineTests: XCTestCase {
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

    // MARK: - Progress

    func testThatProgressClosureIsCalled() {
        let request = ImageRequest(url: defaultURL)

        dataLoader.results[defaultURL] = .success(
            (Data(count: 20), URLResponse(url: defaultURL, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let expectTaskFinished = self.expectation(description: "Task finished")
        let expectProgressFinished = self.expectation(description: "Progress finished")

        var expected: [(Int64, Int64)] = [(10, 20), (20, 20)]
        pipeline.loadImage(
            with: request,
            progress: { _, completed, total in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(expected.first?.0 == completed)
                XCTAssertTrue(expected.first?.1 == total)
                expected.remove(at: 0)
                if expected.isEmpty {
                    expectProgressFinished.fulfill()
                }
            },
            completion: { _,_ in
                expectTaskFinished.fulfill()
        })

        wait()
    }

    func testThatProgressObjectIsUpdated() {
        let request = ImageRequest(url: defaultURL)

        dataLoader.results[defaultURL] = .success(
            (Data(count: 20), URLResponse(url: defaultURL, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let expectTaskFinished = self.expectation(description: "Task finished")

        let task = pipeline.loadImage(with: request) { _,_ in
            expectTaskFinished.fulfill()
        }

        self.expect(values: [20], for: task.progress, keyPath: \.totalUnitCount) { _, _ in
            XCTAssertTrue(Thread.isMainThread)
        }
        self.expect(values: [10, 20], for: task.progress, keyPath: \.completedUnitCount) { _, _ in
            XCTAssertTrue(Thread.isMainThread)
        }

        wait()
    }

    // MARK: - Configuration

    func testOverridingProcessor() {
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageProcessor = { _, _ in
                AnyImageProcessor(MockImageProcessor(id: "processorFromOptions"))
            }
        }

        let request = ImageRequest(url: defaultURL).processed(with: MockImageProcessor(id: "processorFromRequest"))

        expect { fulfill in
            pipeline.loadImage(with: request) { response, _ in
                XCTAssertNotNil(response)
                XCTAssertEqual(response?.image.nk_test_processorIDs.count, 1)
                XCTAssertEqual(response?.image.nk_test_processorIDs.first, "processorFromOptions")
                fulfill()
            }
        }
        wait()
    }

    // MARK: - Animated Images

    func testAnimatedImageArentProcessed() {
        ImagePipeline.Configuration.isAnimatedImageDataEnabled = true

        dataLoader.results[defaultURL] = .success(
            (Test.data(name: "cat", extension: "gif"), Test.urlResponse)
        )

        let expectation = self.expectation(description: "Task finished")
        let request = Test.request.processed(key: "1") { _ in
            XCTFail()
            return nil
        }
        pipeline.loadImage(with: request) { response, _ in
            XCTAssertNotNil(response)
            XCTAssertNotNil(response?.image.animatedImageData)
            expectation.fulfill()
        }

        wait()

        ImagePipeline.Configuration.isAnimatedImageDataEnabled = false
    }

    // MARK: - Updating Priority

    func testThatPriorityIsUpdated() {
        let queue = pipeline.configuration.dataLoadingQueue
        queue.isSuspended = true

        let request = Test.request
        XCTAssertEqual(request.priority, .normal)

        var operation: Foundation.Operation?
        _ = self.keyValueObservingExpectation(for: queue, keyPath: "operations") { (_, _) -> Bool in
            operation = queue.operations.first
            XCTAssertEqual(queue.operations.count, 1)
            return true
        }

        let task = pipeline.loadImage(with: request) { _, _ in
            return
        }

        wait()

        XCTAssertNotNil(operation)
        self.keyValueObservingExpectation(for: operation!, keyPath: "queuePriority") { (_, _) in
            XCTAssertEqual(operation?.queuePriority, .high)
            return true
        }

        // We can't yet test that priority is actually changed, but we can at
        // least run this code path and check that task's priority gets updated.
        XCTAssertEqual(task.request.priority, .normal)
        task.setPriority(.high)
        XCTAssertEqual(task.request.priority, .high)

        wait()
    }

    // MARK: - Cancellation

    func testThatProcessingOperationIsCancelled() {
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        var operation: Foundation.Operation?
        _ = self.keyValueObservingExpectation(for: queue, keyPath: "operations") { (_, _) in
            operation = queue.operations.first
            XCTAssertEqual(queue.operations.count, 1)
            return true
        }

        let request = Test.request.processed(key: "1") {
            XCTFail()
            return $0
        }

        let task = pipeline.loadImage(with: request) { (_, _) in
            XCTFail()
        }

        wait()

        XCTAssertNotNil(operation)
        self.keyValueObservingExpectation(for: operation!, keyPath: "isCancelled") { (_, _) in
            XCTAssertTrue(operation!.isCancelled)
            return true
        }

        task.cancel()

        wait()
    }
}

/// Test how well image pipeline interacts with memory cache.
class ImagePipelineMemoryCacheTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var cache: MockImageCache!
    var loader: ImagePipeline!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        cache = MockImageCache()
        loader = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = cache
        }
    }

    func testThatImageIsLoaded() {
        waitLoadedImage(with: ImageRequest(url: defaultURL))
    }

    // MARK: Caching

    func testCacheWrite() {
        waitLoadedImage(with: Test.request)

        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache.cachedResponse(for: Test.request))
    }

    func testCacheRead() {
        cache.storeResponse(ImageResponse(image: defaultImage, urlResponse: nil), for: Test.request)

        waitLoadedImage(with: Test.request)

        XCTAssertEqual(dataLoader.createdTaskCount, 0)
        XCTAssertNotNil(cache.cachedResponse(for: Test.request))
    }

    func testCacheWriteDisabled() {
        let request = ImageRequest(url: defaultURL).mutated {
            $0.memoryCacheOptions.isWriteAllowed = false
        }

        waitLoadedImage(with: request)

        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNil(cache.cachedResponse(for: Test.request))
    }

    func testCacheReadDisabled() {
        cache.storeResponse(ImageResponse(image: defaultImage, urlResponse: nil), for: Test.request)

        let request = ImageRequest(url: defaultURL).mutated {
            $0.memoryCacheOptions.isReadAllowed = false
        }

        waitLoadedImage(with: request)

        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNotNil(cache.cachedResponse(for: Test.request))
    }

    // MARK: Completion Behavior

    func testCompletionDispatch() {
        _testCompletionDispatch()
    }

    func testCompletionDispatchWhenImageCached() {
        cache.storeResponse(ImageResponse(image: defaultImage, urlResponse: nil), for: Test.request)
        _testCompletionDispatch()
    }

    func _testCompletionDispatch() {
        var isCompleted = false
        expect { fulfill in
            loader.loadImage(with: ImageRequest(url: defaultURL)) { _,_ in
                XCTAssert(Thread.isMainThread)
                isCompleted = true
                fulfill()
            }
        }
        XCTAssertFalse(isCompleted) // must be asynchronous
        wait()
        XCTAssertTrue(isCompleted)
    }

    // MARK: Helpers

    func waitLoadedImage(with request: Nuke.ImageRequest) {
        expect { fulfill in
            loader.loadImage(with: request) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }
        wait()
    }
}

class ImagePipelineErrorHandlingTests: XCTestCase {
    func testThatDataLoadingFailedErrorIsReturned() {
        let dataLoader = MockDataLoader()
        let imagePipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
        dataLoader.results[defaultURL] = .failure(expectedError)

        expect { fulfill in
            imagePipeline.loadImage(with: ImageRequest(url: defaultURL)) { _, error in
                switch error {
                case let .dataLoadingFailed(error)?:
                    XCTAssertEqual((error as NSError).code, expectedError.code)
                    XCTAssertEqual((error as NSError).domain, expectedError.domain)
                default: XCTFail()
                }
                fulfill()
            }
        }
        wait()
    }

    func testThatDecodingFailedErrorIsReturned() {
        let imagePipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageDecoder = { _ in
                return MockFailingDecoder()
            }
            $0.imageCache = nil
        }

        expect { fulfill in
            imagePipeline.loadImage(with: ImageRequest(url: defaultURL)) { _, error in
                switch error {
                case .decodingFailed?: break
                default: XCTFail()
                }
                fulfill()
            }
        }
        wait()
    }

    func testThatProcessingFailedErrorIsReturned() {
        let loader = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            return // !swift(>=4.1)
        }

        let request = ImageRequest(url: defaultURL).processed(with: MockFailingProcessor())

        expect { fulfill in
            loader.loadImage(with: request) { _, error in
                switch error {
                case .processingFailed?: break
                default: XCTFail()
                }
                fulfill()
            }
        }
        wait()
    }
}

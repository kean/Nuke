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
    
    func testThreadSafety() {
        runThreadSafetyTests(for: pipeline)
    }

    // MARK: - Progress

    func testThatProgressClosureIsCalled() {
        let request = ImageRequest(url: defaultURL)

        dataLoader.results[defaultURL] = .success(
            (Data(count: 20), URLResponse(url: defaultURL, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        let expectTaskFinished = makeExpectation()
        let expectProgressFinished = makeExpectation()

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

        let expectTaskFinished = makeExpectation()

        let task = pipeline.loadImage(with: request) { _,_ in
            expectTaskFinished.fulfill()
        }

        let progress = task.progress

        var expectedTotal: [Int64] = [20]
        self.keyValueObservingExpectation(for: progress, keyPath: "totalUnitCount") { (object, _) -> Bool in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(expectedTotal.first, progress.totalUnitCount)
            expectedTotal.removeFirst()
            return expectedTotal.isEmpty
        }

        var expectedCompleted: [Int64] = [10, 20]
        self.keyValueObservingExpectation(for: progress, keyPath: "completedUnitCount") { (object,  _) -> Bool in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(expectedCompleted.first, progress.completedUnitCount)
            expectedCompleted.removeFirst()
            return expectedCompleted.isEmpty
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

    // MARK: - Metrics Collection

    func testThatMetricsAreCollectedWhenTaskCompleted() {
        expect { fulfill in
            pipeline.didFinishCollectingMetrics = { task, metrics in
                XCTAssertEqual(task.taskId, metrics.taskId)
                XCTAssertNotNil(metrics.endDate)
                XCTAssertNotNil(metrics.session)
                XCTAssertNotNil(metrics.session?.endDate)
                fulfill()
            }
        }

        expect { fulfill in
            pipeline.loadImage(with: defaultURL) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }
        wait()
    }

    func testThatMetricsAreCollectedWhenTaskCancelled() {
        expect { fulfill in
            pipeline.didFinishCollectingMetrics = { task, metrics in
                XCTAssertEqual(task.taskId, metrics.taskId)
                XCTAssertTrue(metrics.wasCancelled)
                XCTAssertNotNil(metrics.endDate)
                XCTAssertNotNil(metrics.session)
                XCTAssertNotNil(metrics.session?.endDate)
                fulfill()
            }
        }

        dataLoader.queue.isSuspended = true

        let task = pipeline.loadImage(with: defaultURL) { _,_ in
            XCTFail()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            task.cancel()
        }
        wait()
    }
}

class ImagePipelineDeduplicationTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var imagePipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        imagePipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    func testThatEquivalentRequestsAreDeduplicated() {
        dataLoader.queue.isSuspended = true

        let request1 = ImageRequest(url: defaultURL)
        let request2 = ImageRequest(url: defaultURL)
        XCTAssertEqual(ImageRequest.LoadKey(request: request1), ImageRequest.LoadKey(request: request2))

        expect { fulfill in
            imagePipeline.loadImage(with: request1) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }

        expect { fulfill in
            imagePipeline.loadImage(with: request2) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testThatNonEquivalentRequestsAreNotDeduplicated() {
        let request1 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = ImageRequest(urlRequest: URLRequest(url: defaultURL, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))
        XCTAssertNotEqual(ImageRequest.LoadKey(request: request1), ImageRequest.LoadKey(request: request2))

        expect { fulfill in
            imagePipeline.loadImage(with: request1) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }

        expect { fulfill in
            imagePipeline.loadImage(with: request2) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }
        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 2)
        }
    }

    func testThatDeduplicatedRequestIsNotCancelledAfterSingleUnsubsribe() {
        dataLoader.queue.isSuspended = true

        // We test it using Manager because Loader is not required
        // to call completion handler for cancelled requests.

        // We don't expect completion to be called.
        let task = imagePipeline.loadImage(with: ImageRequest(url: defaultURL)) { _,_ in
            XCTFail()
        }

        expect { fulfill in // This work we don't cancel
            imagePipeline.loadImage(with: ImageRequest(url: defaultURL)) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }

        task.cancel()
        self.dataLoader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testThatProgressIsReported() {
        dataLoader.results[defaultURL] = .success(
            (Data(count: 20), URLResponse(url: defaultURL, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )
        dataLoader.queue.isSuspended = true

        for _ in 0..<3 {
            let request = ImageRequest(url: defaultURL)

            let expectTaskFinished = makeExpectation()
            let expectProgressFinished = makeExpectation()

            var expected: [(Int64, Int64)] = [(10, 20), (20, 20)]
            imagePipeline.loadImage(
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
        }
        dataLoader.queue.isSuspended = false

        wait()
    }

    func testDisablingDeduplication() {
        let imagePipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.isDeduplicationEnabled = false
        }

        dataLoader.queue.isSuspended = true

        let request1 = ImageRequest(url: defaultURL)
        let request2 = ImageRequest(url: defaultURL)
        XCTAssertEqual(request1.loadKey, request2.loadKey)

        expect { fulfill in
            imagePipeline.loadImage(with: request1) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }

        expect { fulfill in
            imagePipeline.loadImage(with: request2) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }
        dataLoader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 2)
        }
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
            $0.memoryCacheOptions.writeAllowed = false
        }

        waitLoadedImage(with: request)

        XCTAssertEqual(dataLoader.createdTaskCount, 1)
        XCTAssertNil(cache.cachedResponse(for: Test.request))
    }

    func testCacheReadDisabled() {
        cache.storeResponse(ImageResponse(image: defaultImage, urlResponse: nil), for: Test.request)

        let request = ImageRequest(url: defaultURL).mutated {
            $0.memoryCacheOptions.readAllowed = false
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
    func testThatLoadingFailedErrorIsReturned() {
        let dataLoader = MockDataLoader()
        let imagePipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }

        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
        dataLoader.results[defaultURL] = .failure(expectedError)

        expect { fulfill in
            imagePipeline.loadImage(with: ImageRequest(url: defaultURL)) { _, error in
                guard let error = error else { XCTFail(); return }
                XCTAssertNotNil(error)
                XCTAssertEqual((error as NSError).code, expectedError.code)
                XCTAssertEqual((error as NSError).domain, expectedError.domain)
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
                guard let error = error else { XCTFail(); return }
                XCTAssertTrue((error as! ImagePipeline.Error) == ImagePipeline.Error.decodingFailed)
                fulfill()
            }
        }
        wait()
    }

    func testThatProcessingFailedErrorIsReturned() {
        let loader = ImagePipeline {
            $0.dataLoader = MockDataLoader()
        }

        let request = ImageRequest(url: defaultURL).processed(with: MockFailingProcessor())

        expect { fulfill in
            loader.loadImage(with: request) { _, error in
                guard let error = error else { XCTFail(); return }
                XCTAssertTrue((error as! ImagePipeline.Error) == ImagePipeline.Error.processingFailed)
                fulfill()
            }
        }
        wait()
    }
}

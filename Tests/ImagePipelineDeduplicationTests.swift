// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineDeduplicationTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!
    var observations = [NSKeyValueObservation]()


    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    func testThatEquivalentRequestsAreDeduplicated() {
        dataLoader.queue.isSuspended = true

        var processingCount = 0
        let request1 = ImageRequest(url: defaultURL).processed(key: "key1") {
            processingCount += 1
            return $0
        }
        let request2 = ImageRequest(url: defaultURL).processed(key: "key1")  {
            processingCount += 1
            return $0
        }
        XCTAssertEqual(ImageRequest.LoadKey(request: request1), ImageRequest.LoadKey(request: request2))

        expect { fulfill in
            pipeline.loadImage(with: request1) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }

        expect { fulfill in
            pipeline.loadImage(with: request2) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(processingCount, 1)
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testThatRequestsWithDifferenteProcessorsAreDeduplicated() {
        dataLoader.queue.isSuspended = true

        let request1 = ImageRequest(url: defaultURL)
            .processed(key: "key1") { $0 }
        let request2 = ImageRequest(url: defaultURL)
            .processed(key: "key2") { $0 }
        XCTAssertEqual(ImageRequest.LoadKey(request: request1), ImageRequest.LoadKey(request: request2))

        expect { fulfill in
            pipeline.loadImage(with: request1) { response, _ in
                XCTAssertNotNil(response)
                fulfill()
            }
        }

        expect { fulfill in
            pipeline.loadImage(with: request2) { response, _ in
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

        let expectation1 = self.expectation(description: "First request completed")
        pipeline.loadImage(with: request1) { response, _ in
            XCTAssertNotNil(response)
            expectation1.fulfill()
        }

        let expectation2 = self.expectation(description: "Second request completed")
        pipeline.loadImage(with: request2) { response, _ in
            XCTAssertNotNil(response)
            expectation2.fulfill()
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
        let task = pipeline.loadImage(with: ImageRequest(url: defaultURL)) { _,_ in
            XCTFail()
        }

        let expectation = self.expectation(description: "Image loaded")
        pipeline.loadImage(with: ImageRequest(url: defaultURL)) { response, _ in
            XCTAssertNotNil(response)
            expectation.fulfill()
        }

        task.cancel()
        self.dataLoader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testSubscribingToExisingSessionWhenProcessingAlreadyStarted() {
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true

        let request1 = ImageRequest(url: defaultURL).processed(key: "key1") { $0 }
        let request2 = ImageRequest(url: defaultURL).processed(key: "key2") { $0 }

        let expectation1 = self.expectation(description: "First request completed")
        let expectation2 = self.expectation(description: "Second request completed")

        let observation = queue.observe(\.operations) { (_, _) in
            XCTAssertEqual(queue.operations.count, 1)
            DispatchQueue.main.async {
                self.pipeline.loadImage(with: request2) { response, _ in
                    XCTAssertNotNil(response)
                    expectation2.fulfill()
                }
                queue.isSuspended = false
            }
            self.observations[0].invalidate()
        }
        self.observations.append(observation)

        pipeline.loadImage(with: request1) { response, _ in
            XCTAssertNotNil(response)
            expectation1.fulfill()
        }

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    // MARK: - Misc

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

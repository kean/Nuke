// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke


class LoaderTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var loader: Loader!
    
    override func setUp() {
        super.setUp()
        
        dataLoader = MockDataLoader()
        loader = Loader(loader: dataLoader)
    }
    
    func testThreadSafety() {
        runThreadSafetyTests(for: loader)
    }

    // MARK: Progress

    func testThatProgressIsReported() {
        var request = Request(url: defaultURL)
        expect { fulfill in
            var expected: [(Int64, Int64)] = [(10, 20), (20, 20)]
            request.progress = {
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(expected.first?.0 == $0)
                XCTAssertTrue(expected.first?.1 == $1)
                expected.remove(at: 0)
                if expected.isEmpty {
                    fulfill()
                }
            }
        }
        expect { fulfill in
            loader.loadImage(with: request) { _ in
                fulfill()
            }
        }
        wait()
    }

    // MARK: Options

    func testOverridingProcessor() {
        var options = Loader.Options()
        options.processor = { (_,_) in AnyProcessor(MockImageProcessor(id: "processorFromOptions")) }

        let loader = Loader(loader: dataLoader, options: options)

        let request = Request(url: defaultURL).processed(with: MockImageProcessor(id: "processorFromRequest"))

        expect { fulfill in
            loader.loadImage(with: request) {
                XCTAssertNotNil($0.value)
                XCTAssertEqual($0.value?.nk_test_processorIDs.count, 1)
                XCTAssertEqual($0.value?.nk_test_processorIDs.first, "processorFromOptions")
                fulfill()
            }
        }
        wait()
    }
}


class LoaderErrorHandlingTests: XCTestCase {
    func testThatLoadingFailedErrorIsReturned() {
        let dataLoader = MockDataLoader()
        let loader = Loader(loader: dataLoader)

        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
        dataLoader.results[defaultURL] = .failure(expectedError)

        expect { fulfill in
            loader.loadImage(with: Request(url: defaultURL)) {
                guard let error = $0.error else { XCTFail(); return }
                XCTAssertNotNil(error)
                XCTAssertEqual((error as NSError).code, expectedError.code)
                XCTAssertEqual((error as NSError).domain, expectedError.domain)
                fulfill()
            }
        }
        wait()
    }

    func testThatDecodingFailedErrorIsReturned() {
        let loader = Loader(loader: MockDataLoader(), decoder: MockFailingDecoder())

        expect { fulfill in
            loader.loadImage(with: Request(url: defaultURL)) {
                guard let error = $0.error else { XCTFail(); return }
                XCTAssertTrue((error as! Loader.Error) == Loader.Error.decodingFailed)
                fulfill()
            }
        }
        wait()
    }

    func testThatProcessingFailedErrorIsReturned() {
        let loader = Loader(loader: MockDataLoader())

        let request = Request(url: defaultURL).processed(with: MockFailingProcessor())

        expect { fulfill in
            loader.loadImage(with: request) {
                guard let error = $0.error else { XCTFail(); return }
                XCTAssertTrue((error as! Loader.Error) == Loader.Error.processingFailed)
                fulfill()
            }
        }
        wait()
    }
}


class LoaderDeduplicationTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var loader: Loader!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        loader = Loader(loader: dataLoader)
    }

    func testThatEquivalentRequestsAreDeduplicated() {
        dataLoader.queue.isSuspended = true

        let request1 = Request(url: defaultURL)
        let request2 = Request(url: defaultURL)
        XCTAssertEqual(request1.loadKey, request2.loadKey)

        expect { fulfill in
            loader.loadImage(with: request1) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }

        expect { fulfill in
            loader.loadImage(with: request2) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }

        dataLoader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testThatNonEquivalentRequestsAreNotDeduplicated() {
        let request1 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 0))
        let request2 = Request(urlRequest: URLRequest(url: defaultURL, cachePolicy: .returnCacheDataDontLoad, timeoutInterval: 0))
        XCTAssertNotEqual(request1.loadKey, request2.loadKey)

        expect { fulfill in
            loader.loadImage(with: request1) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }

        expect { fulfill in
            loader.loadImage(with: request2) {
                XCTAssertNotNil($0.value)
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
        let cts = CancellationTokenSource()

        // We expect completion to get called, since it going to be "retained" by
        // other request.
        expect { fulfill in
            loader.loadImage(with: Request(url: defaultURL), token: cts.token) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }

        expect { fulfill in // This work we don't cancel
            loader.loadImage(with: Request(url: defaultURL), token: nil) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }

        cts.cancel()
        self.dataLoader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 1)
        }
    }

    func testThatProgressIsReported() {
        dataLoader.queue.isSuspended = true

        for _ in 0..<3 {
            var request = Request(url: defaultURL)
            expect { fulfill in
                var expected: [(Int64, Int64)] = [(10, 20), (20, 20)]
                request.progress = {
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertTrue(expected.first?.0 == $0)
                    XCTAssertTrue(expected.first?.1 == $1)
                    expected.remove(at: 0)
                    if expected.isEmpty {
                        fulfill()
                    }
                }
            }
            expect { fulfill in
                loader.loadImage(with: request) { _ in
                    fulfill()
                }
            }
        }
        dataLoader.queue.isSuspended = false

        wait()
    }

    func testDisablingDeduplication() {
        var options = Loader.Options()
        options.isDeduplicationEnabled = false

        let loader = Loader(loader: dataLoader, options: options)

        dataLoader.queue.isSuspended = true

        let request1 = Request(url: defaultURL)
        let request2 = Request(url: defaultURL)
        XCTAssertEqual(request1.loadKey, request2.loadKey)

        expect { fulfill in
            loader.loadImage(with: request1) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }

        expect { fulfill in
            loader.loadImage(with: request2) {
                XCTAssertNotNil($0.value)
                fulfill()
            }
        }
        dataLoader.queue.isSuspended = false

        wait { _ in
            XCTAssertEqual(self.dataLoader.createdTaskCount, 2)
        }
    }
}

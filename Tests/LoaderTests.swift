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

// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class LoaderTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var loader: Loader!
    
    override func setUp() {
        super.setUp()
        
        dataLoader = MockDataLoader()
        loader = Loader(loader: dataLoader, decoder: DataDecoder(), cache: nil)
    }
    
    func testThreadSafety() {
        runThreadSafetyTests(for: loader)
    }
}

class LoaderErrorHandlingTests: XCTestCase {

    func testThatLoadingFailedErrorIsReturned() {
        let dataLoader = MockDataLoader()
        let loader = Loader(loader: dataLoader, decoder: DataDecoder(), cache: nil)

        let expectedError = NSError(domain: "t", code: 23, userInfo: nil)
        dataLoader.results[defaultURL] = .rejected(expectedError)

        expect { fulfill in
            loader.loadImage(with: Request(url: defaultURL))
                .catch { error in
                    XCTAssertNotNil(error)
                    XCTAssertEqual((error as NSError).code, expectedError.code)
                    XCTAssertEqual((error as NSError).domain, expectedError.domain)
                    fulfill()
            }
        }
        wait()
    }

    func testThatDecodingFailedErrorIsReturned() {
        let loader = Loader(loader: MockDataLoader(), decoder: MockFailingDecoder(), cache: nil)

        expect { fulfill in
            _ = loader.loadImage(with: Request(url: defaultURL)).catch { error in
                XCTAssertTrue((error as! Loader.Error) == Loader.Error.decodingFailed)
                fulfill()
            }
        }
        wait()
    }

    func testThatProcessingFailedErrorIsReturned() {
        let loader = Loader(loader: MockDataLoader(), decoder: DataDecoder(), cache: nil)

        let request = Request(url: defaultURL).processed(with: MockFailingProcessor())

        expect { fulfill in
            _ = loader.loadImage(with: request).catch { error in
                XCTAssertTrue((error as! Loader.Error) == Loader.Error.processingFailed)
                fulfill()
            }
        }
        wait()
    }
}

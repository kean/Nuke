// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ProcessingTests: XCTestCase {
    var mockMemoryCache: MockCache!
    var mockSessionManager: MockDataLoader!
    var loader: Loader!

    override func setUp() {
        super.setUp()

        mockSessionManager = MockDataLoader()
        mockMemoryCache = MockCache()
        
        mockSessionManager = MockDataLoader()
        loader = Loader(loader: mockSessionManager, decoder: DataDecoder(), cache: mockMemoryCache)
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Applying Filters

    func testThatImageIsProcessed() {
        var request = Request(url: defaultURL)
        request.add(processor: MockImageProcessor(ID: "processor1"))

        expect { fulfill in
            _ = loader.loadImage(with: request).then { image in
                XCTAssertEqual(image.nk_test_processorIDs, ["processor1"])
                fulfill()
            }
        }
        wait()
    }

    func testThatProcessedImageIsMemCached() {
        expect { fulfill in
            var request = Request(url: defaultURL)
            request.add(processor: MockImageProcessor(ID: "processor1"))

            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()

        var request = Request(url: defaultURL)
        request.add(processor: MockImageProcessor(ID: "processor1"))
        guard let image = mockMemoryCache.image(for: request) else {
            XCTFail()
            return
        }
        XCTAssertEqual(image.nk_test_processorIDs, ["processor1"])
    }

    // MARK: Composing Filters

    func testThatImageIsProcessedWithFilterComposition() {
        var request = Request(url: defaultURL)
        request.add(processor: MockImageProcessor(ID: "processor1"))
        request.add(processor: MockImageProcessor(ID: "processor2"))

        expect { fulfill in
            _ = loader.loadImage(with: request).then {
                XCTAssertEqual($0.nk_test_processorIDs, ["processor1", "processor2"])
                fulfill()
            }
        }
        wait()
    }

    func testThatImageProcessedWithFilterCompositionIsMemCached() {
        expect { fulfill in
            var request = Request(url: defaultURL)
            request.add(processor: MockImageProcessor(ID: "processor1"))
            request.add(processor: MockImageProcessor(ID: "processor2"))
            _ = loader.loadImage(with: request).then { _ in
                fulfill()
            }
        }
        wait()

        var request = Request(url: defaultURL)
        request.add(processor: MockImageProcessor(ID: "processor1"))
        request.add(processor: MockImageProcessor(ID: "processor2"))
        guard let image = mockMemoryCache.image(for: request) else {
            XCTFail()
            return
        }
        XCTAssertEqual(image.nk_test_processorIDs, ["processor1", "processor2"])
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class ProcessingTests: XCTestCase {
    var mockSessionManager: MockDataLoader!
    var loader: Loader!

    override func setUp() {
        super.setUp()

        mockSessionManager = MockDataLoader()
        loader = Loader(loader: mockSessionManager)
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Applying Filters

    func testThatImageIsProcessed() {
        let request = Request(url: defaultURL).processed(with: MockImageProcessor(ID: "processor1"))

        expect { fulfill in
            loader.loadImage(with: request) {
                guard let image = $0.value else { XCTFail(); return }
                XCTAssertEqual(image.nk_test_processorIDs, ["processor1"])
                fulfill()
            }
        }
        wait()
    }

    // MARK: Composing Filters

    func testThatImageIsProcessedWithFilterComposition() {
        let request = Request(url: defaultURL)
            .processed(with: MockImageProcessor(ID: "processor1"))
            .processed(with: MockImageProcessor(ID: "processor2"))

        expect { fulfill in
            loader.loadImage(with: request) {
                guard let image = $0.value else { XCTFail(); return }
                XCTAssertEqual(image.nk_test_processorIDs, ["processor1", "processor2"])
                fulfill()
            }
        }
        wait()
    }
}

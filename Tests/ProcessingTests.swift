// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

#if !os(macOS)
    import UIKit
#endif

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
        let request = Request(url: defaultURL).processed(with: MockImageProcessor(id: "processor1"))

        expect { fulfill in
            loader.loadImage(with: request) {
                guard let image = $0.value else { XCTFail(); return }
                XCTAssertEqual(image.nk_test_processorIDs, ["processor1"])
                fulfill()
            }
        }
        wait()
    }

    // MARK: Anonymous Processors

    func testAnonymousProcessorKeys() {
        XCTAssertEqual(
            Request(url: defaultURL).processed(key: 1, { $0 }).cacheKey,
            Request(url: defaultURL).processed(key: 1, { $0 }).cacheKey
        )

        XCTAssertNotEqual(
            Request(url: defaultURL).processed(key: 1, { $0 }).cacheKey,
            Request(url: defaultURL).processed(key: 2, { $0 }).cacheKey
        )
    }

    func testAnonymousProcessorIsApplied() {
        let request = Request(url: defaultURL).processed(key: 1) {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }
        let image = request.processor?.process(Image())
        XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["1"])
    }

    func testAnonymousProcessorIsApplied2() {
        var request = Request(url: defaultURL)
        request.process(key: 1) {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }
        let image = request.processor?.process(Image())
        XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["1"])
    }

    // MARK: Composing Filters

    func testThatImageIsProcessedWithFilterComposition() {
        let request = Request(url: defaultURL)
            .processed(with: MockImageProcessor(id: "processor1"))
            .processed(with: MockImageProcessor(id: "processor2"))

        expect { fulfill in
            loader.loadImage(with: request) {
                guard let image = $0.value else { XCTFail(); return }
                XCTAssertEqual(image.nk_test_processorIDs, ["processor1", "processor2"])
                fulfill()
            }
        }
        wait()
    }

    // MARK: Resizing

    #if !os(macOS)
    func testResizingUsingRequestParameters() {
        let request = Request(url: defaultURL, targetSize: CGSize(width: 40, height: 40), contentMode: .aspectFit)
        let image = request.processor!.process(defaultImage)
        XCTAssertEqual(image?.cgImage?.width, 40)
        XCTAssertEqual(image?.cgImage?.height, 30)
    }
    #endif
}

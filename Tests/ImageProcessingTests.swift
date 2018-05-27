// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if !os(macOS)
    import UIKit
#endif

class ImageProcessingTests: XCTestCase {
    var mockDataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        mockDataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = mockDataLoader
            return // !swift(>=4.1)
        }
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: Applying Filters

    func testThatImageIsProcessed() {
        let request = ImageRequest(url: defaultURL).processed(with: MockImageProcessor(id: "processor1"))

        expect { fulfill in
            pipeline.loadImage(with: request) { response, _ in
                guard let image = response?.image else { XCTFail(); return }
                XCTAssertEqual(image.nk_test_processorIDs, ["processor1"])
                fulfill()
            }
        }
        wait()
    }

    // MARK: Anonymous Processors

    func testAnonymousProcessorKeys() {
        XCTAssertEqual(
            ImageRequest.CacheKey(request:
                ImageRequest(url: defaultURL).processed(key: 1, { $0 })
            ),
            ImageRequest.CacheKey(request:
                ImageRequest(url: defaultURL).processed(key: 1, { $0 })
            )
        )

        XCTAssertNotEqual(
            ImageRequest.CacheKey(request:
                ImageRequest(url: defaultURL).processed(key: 1, { $0 })
            ),
            ImageRequest.CacheKey(request:
                ImageRequest(url: defaultURL).processed(key: 2, { $0 })
            )
        )
    }

    func testAnonymousProcessorIsApplied() {
        let request = ImageRequest(url: defaultURL).processed(key: 1) {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)
        let image = request.processor?.process(image: Image(), context: context)
        XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["1"])
    }

    func testAnonymousProcessorIsApplied2() {
        var request = ImageRequest(url: defaultURL)
        request.process(key: 1) {
            $0.nk_test_processorIDs = ["1"]
            return $0
        }
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)
        let image = request.processor?.process(image: Image(), context: context)
        XCTAssertEqual(image?.nk_test_processorIDs ?? [], ["1"])
    }

    // MARK: Composing Filters

    func testApplyingMultipleProcessors() {
        let request = ImageRequest(url: defaultURL)
            .processed(with: MockImageProcessor(id: "processor1"))
            .processed(with: MockImageProcessor(id: "processor2"))

        expect { fulfill in
            pipeline.loadImage(with: request) { response, _ in
                guard let image = response?.image else { XCTFail(); return }
                XCTAssertEqual(image.nk_test_processorIDs, ["processor1", "processor2"])
                fulfill()
            }
        }
        wait()
    }

    func testPerformingRequestWithoutProcessors() {
        var request = ImageRequest(url: defaultURL)
        request.processor = nil
        request.process(with: MockImageProcessor(id: "processor1"))

        expect { fulfill in
            pipeline.loadImage(with: request) { response, _ in
                guard let image = response?.image else { XCTFail(); return }
                XCTAssertEqual(image.nk_test_processorIDs, ["processor1"])
                fulfill()
            }
        }
        wait()
    }

    // MARK: Resizing

    #if !os(macOS)
    func testResizingUsingRequestParameters() {
        let request = ImageRequest(url: defaultURL, targetSize: CGSize(width: 40, height: 40), contentMode: .aspectFit)
        let context = ImageProcessingContext(request: request, isFinal: true, scanNumber: nil)
        let image = request.processor!.process(image: defaultImage, context: context)
        XCTAssertEqual(image?.cgImage?.width, 40)
        XCTAssertEqual(image?.cgImage?.height, 30)
    }
    #endif
}

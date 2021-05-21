// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
import Combine
@testable import Nuke

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
class ImagePipelinePublisherTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var imageCache: MockImageCache!
    var dataCache: MockDataCache!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        imageCache = MockImageCache()
        dataCache = MockDataCache()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.dataCache = dataCache
        }
    }

    func testLoadWithPublisher() throws {
        // GIVEN
        let request = ImageRequest(id: "a", data: Just(Test.data))

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN
        let image = try XCTUnwrap(record.image)
        XCTAssertEqual(image.sizeInPixels, CGSize(width: 640, height: 480))
    }

    func testLoadWithPublisherAndApplyProcessor() throws {
        // GIVEN
        var request = ImageRequest(id: "a", data: Just(Test.data))
        request.processors = [MockImageProcessor(id: "1")]

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN
        let image = try XCTUnwrap(record.image)
        XCTAssertEqual(image.sizeInPixels, CGSize(width: 640, height: 480))
        XCTAssertEqual(image.nk_test_processorIDs, ["1"])
    }

    func testImageRequestWithPublisher() {
        // GIVEN
        let request = ImageRequest(id: "a", data: Just(Test.data))

        // THEN
        XCTAssertNil(request.urlRequest)
        XCTAssertNil(request.url)
    }
}

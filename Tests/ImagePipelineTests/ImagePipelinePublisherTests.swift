// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

#if canImport(Combine)
import Combine

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
        #warning("fix how error is populated")
        let request = ImageRequest(id: "a", data: Just(Test.data).setFailureType(to: Swift.Error.self))

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN
        let image = try XCTUnwrap(record.image)
        XCTAssertEqual(image.sizeInPixels, CGSize(width: 640, height: 480))
    }

    func testLoadWithPublisherAndApplyProcessor() throws {
        // GIVEN
        var request = ImageRequest(id: "a", data: Just(Test.data).setFailureType(to: Swift.Error.self))
        request.processors = [MockImageProcessor(id: "1")]

        // WHEN
        let record = expect(pipeline).toLoadImage(with: request)
        wait()

        // THEN
        let image = try XCTUnwrap(record.image)
        XCTAssertEqual(image.sizeInPixels, CGSize(width: 640, height: 480))
        XCTAssertEqual(image.nk_test_processorIDs, ["1"])
    }
}

#endif

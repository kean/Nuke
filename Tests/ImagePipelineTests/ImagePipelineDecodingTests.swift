// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineDecodingTests: XCTestCase {
    var dataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        dataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    func testExperimentalDecoder() throws {
        // Given
        let decoder = MockExperimentalDecoder()

        let dummyImage = PlatformImage()
        let dummyData = "123".data(using: .utf8)
        decoder._decode = { data in
            return ImageContainer(image: dummyImage, data: dummyData, userInfo: ["a": 1])
        }

        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }

        // When
        var response: ImageResponse?
        expect(pipeline).toLoadImage(with: Test.request, completion: {
            response = $0.value
        })
        wait()

        // Then
        let container = try XCTUnwrap(response?.container)
        XCTAssertNotNil(container.image)
        XCTAssertEqual(container.data, dummyData)
        XCTAssertEqual(container.userInfo["a"] as? Int, 1)
    }
}

private final class MockExperimentalDecoder: ImageDecoding {
    var _decode: ((Data) -> ImageContainer?)!

    func decode(_ data: Data) -> ImageContainer? {
        return _decode(data)
    }
}

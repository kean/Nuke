// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

/// Test how well image pipeline interacts with memory cache.
class ImageRequestConvertibleTests: XCTestCase {
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

    func testPassURL() {
        // Given
        let input = URL(string: "https://example.com/image.jpg")!

        // When/Then
        let expectation = self.expectation(description: "ImageLoaded")
        pipeline.loadImage(with: input) {
            XCTAssertTrue($0.isSuccess)
            expectation.fulfill()
        }
        wait()
    }

    func testPassURLRequest() {
        // Given
        let input = URLRequest(url: URL(string: "https://example.com/image.jpg")!)

        // When/Then
        let expectation = self.expectation(description: "ImageLoaded")
        pipeline.loadImage(with: input) {
            XCTAssertTrue($0.isSuccess)
            expectation.fulfill()
        }
        wait()
    }

    func testPassImageRequest() {
        // Given
        let input = ImageRequest(url: URL(string: "https://example.com/image.jpg")!)

        // When/Then
        let expectation = self.expectation(description: "ImageLoaded")
        pipeline.loadImage(with: input) {
            XCTAssertTrue($0.isSuccess)
            expectation.fulfill()
        }
        wait()
    }
}

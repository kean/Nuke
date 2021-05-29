// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageViewIntegrationTests: XCTestCase {
    var imageView: _ImageView!
    var pipeline: ImagePipeline!

    override func setUp() {
        super.setUp()

        pipeline = ImagePipeline {
            $0.dataLoader = DataLoader()
            $0.imageCache = MockImageCache()
        }

        // Nuke.loadImage(...) methods use shared pipeline by default.
        ImagePipeline.pushShared(pipeline)

        imageView = _ImageView()
    }

    override func tearDown() {
        ImagePipeline.popShared()
    }

    var url: URL {
        return Test.url(forResource: "fixture", extension: "jpeg")
    }

    var request: ImageRequest {
        return ImageRequest(url: url)
    }

    // MARK: - Loading

    func testImageLoaded() {
        // When
        expectToLoadImage(with: request, into: imageView)
        wait()

        // Then
        XCTAssertNotNil(imageView.image)
    }

    func testImageLoadedWithURL() {

        Nuke.loadImage(with: url, into: imageView)

        // When
        let expectation = self.expectation(description: "Image loaded")
        Nuke.loadImage(with: url, into: imageView) { _ in
            expectation.fulfill()
        }
        wait()

        // Then
        XCTAssertNotNil(imageView.image)
    }

    // MARK: - Loading with Invalid URL

    func testLoadImageWithInvalidURLString() {
        // WHEN
        let expectation = self.expectation(description: "Image loaded")
        Nuke.loadImage(with: "http://example.com/invalid url", into: imageView) { result in
            XCTAssertNotNil(result.error?.dataLoadingError)
            expectation.fulfill()
        }
        wait()

        // THEN
        XCTAssertNil(imageView.image)
    }

    func testLoadingWithNilURL() {
        // GIVEN
        var urlRequest = URLRequest(url: Test.url)
        urlRequest.url = nil // Not sure why this is even possible

        // WHEN
        let expectation = self.expectation(description: "Image loaded")
        Nuke.loadImage(with: urlRequest, into: imageView) { result in
            // THEN
            XCTAssertNotNil(result.error?.dataLoadingError)
            expectation.fulfill()
        }
        wait()

        // THEN
        XCTAssertNil(imageView.image)
    }

    func testLoadingWithRequestWithNilURL() {
        // GIVEN
        let input = ImageRequest(url: nil)

        // WNEN/THEN
        let expectation = self.expectation(description: "ImageLoaded")
        pipeline.loadImage(with: input) {
            XCTAssertTrue($0.isFailure)
            XCTAssertNoThrow($0.error?.dataLoadingError)
            expectation.fulfill()
        }
        wait()
    }

    // MARK: - Data Passed

    #if os(iOS)
    private final class MockView: UIView, Nuke_ImageDisplaying {
        func nuke_display(image: PlatformImage?, data: Data?) {
            recordedData.append(data)
        }

        var recordedData = [Data?]()
    }

    func testThatAttachedDataIsPassed() throws {
        // GIVEN
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in
                ImageDecoders.Empty()
            }
        }

        let imageView = MockView()

        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        options.isPrepareForReuseEnabled = false

        // WHEN
        let expectation = self.expectation(description: "Image loaded")
        Nuke.loadImage(with: Test.url, options: options, into: imageView) { result in
            XCTAssertNotNil(result.value)
            XCTAssertNotNil(result.value?.container.data)
            expectation.fulfill()
        }
        wait()

        // THEN
        let data = try XCTUnwrap(imageView.recordedData.first)
        XCTAssertNotNil(data)
    }


    #endif
}


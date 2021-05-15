// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke
@testable import NukeUI

class ImageViewIntegrationTests: XCTestCase {
    var imageView: _ImageView!

    override func setUp() {
        super.setUp()

        let pipeline = ImagePipeline {
            $0.dataLoader = DataLoader()
            $0.imageCache = ImageCache()
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

        NukeUI.loadImage(with: url, into: imageView)

        // When
        let expectation = self.expectation(description: "Image loaded")
        NukeUI.loadImage(with: url, into: imageView) { _ in
            expectation.fulfill()
        }
        wait()

        // Then
        XCTAssertNotNil(imageView.image)
    }

    // MARK: - Loading with Invalid URL

    func testLoadImageWithInvalidURLString() {
        // When
        let expectation = self.expectation(description: "Image loaded")
        Nuke.loadImage(with: "http://example.com/invalid url", into: imageView) { result in
            XCTAssertNotNil(result.error?.dataLoadingError)
            expectation.fulfill()
        }
        wait()

        // Then
        XCTAssertNil(imageView.image)
    }
}

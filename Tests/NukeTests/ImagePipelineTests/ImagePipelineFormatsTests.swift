// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineFormatsTests: XCTestCase {
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

    func testExtendedColorSpaceSupport() throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Test.data(name: "image-p3", extension: "jpg"), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        var result: Result<ImageResponse, ImagePipeline.Error>?
        expect(pipeline).toLoadImage(with: Test.request) {
            result = $0
        }
        wait()

        // Then
        let image = try XCTUnwrap(result?.value?.image)
        let cgImage = try XCTUnwrap(image.cgImage)
        let colorSpace = try XCTUnwrap(cgImage.colorSpace)
#if os(iOS) || os(tvOS) || os(macOS)
        XCTAssertTrue(colorSpace.isWideGamutRGB)
#elseif os(watchOS)
        XCTAssertFalse(colorSpace.isWideGamutRGB)
#endif
    }

    func testGrayscaleSupport() throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Test.data(name: "grayscale", extension: "jpeg"), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        var result: Result<ImageResponse, ImagePipeline.Error>?
        expect(pipeline).toLoadImage(with: Test.request) {
            result = $0
        }
        wait()

        // Then
        let image = try XCTUnwrap(result?.value?.image)
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cgImage.bitsPerComponent, 8)
    }
}

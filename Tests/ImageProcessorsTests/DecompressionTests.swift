// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImageDecompressionTests: XCTestCase {

    func testDecompressionNotNeededFlagSet() throws {
        // Given
        let input = Test.image
        ImageDecompression.setDecompressionNeeded(true, for: input)

        // When
        let output = ImageDecompression.decompress(image: input)

        // Then
        XCTAssertFalse(ImageDecompression.isDecompressionNeeded(for: output) ?? false)
    }

    func testGrayscalePreserved() throws {
        // Given
        let input = Test.image(named: "grayscale", extension: "jpeg")
        XCTAssertEqual(input.cgImage?.bitsPerComponent, 8)
        XCTAssertEqual(input.cgImage?.bitsPerPixel, 8)

        // When
        let output = ImageDecompression.decompress(image: input)

        // Then
        // The original image doesn't have an alpha channel (kCGImageAlphaNone),
        // but this parameter combination (8 bbc and kCGImageAlphaNone) is not
        // supported by CGContext. Thus we are switching to a different format.
        XCTAssertEqual(output.cgImage?.bitsPerPixel, 16)
        XCTAssertEqual(output.cgImage?.bitsPerComponent, 8)
    }
}

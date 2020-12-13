// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

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
        XCTAssertFalse(try XCTUnwrap(ImageDecompression.isDecompressionNeeded(for: output)))
    }

    func testGrayscalePreserved() throws {
        // Given
        let input = Test.image(named: "grayscale", extension: "jpeg")
        XCTAssertEqual(input.cgImage?.bitsPerComponent, 8)
        XCTAssertEqual(input.cgImage?.bitsPerPixel, 8)

        // When
        let output = ImageDecompression.decompress(image: input)

        // Then
        XCTAssertEqual(output.cgImage?.bitsPerComponent, 8)
        #if os(macOS)
        XCTAssertEqual(output.cgImage?.bitsPerPixel, 8)
        #else
        XCTAssertEqual(output.cgImage?.bitsPerPixel, 16)
        #endif
    }
}

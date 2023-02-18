// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

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
        let output = ImageDecompression.decompress(image: input, isUsingPrepareForDisplay: true)

        // Then
        // The original image doesn't have an alpha channel (kCGImageAlphaNone),
        // but this parameter combination (8 bbc and kCGImageAlphaNone) is not
        // supported by CGContext. Thus we are switching to a different format.
#if os(iOS) || os(tvOS)
        if #available(iOS 15.0, tvOS 15.0, *) {
            XCTAssertEqual(output.cgImage?.bitsPerPixel, 8) // Yay, preparingForDisplay supports it
            XCTAssertEqual(output.cgImage?.bitsPerComponent, 8)
        } else {
            XCTAssertEqual(output.cgImage?.bitsPerPixel, 16)
            XCTAssertEqual(output.cgImage?.bitsPerComponent, 8)
        }
#else
        XCTAssertEqual(output.cgImage?.bitsPerPixel, 16)
        XCTAssertEqual(output.cgImage?.bitsPerComponent, 8)
#endif
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite struct ImageDecompressionTests {

    @Test func decompressionNotNeededFlagSet() throws {
        // Given
        let input = Test.image
        ImageDecompression.setDecompressionNeeded(true, for: input)

        // When
        let output = ImageDecompression.decompress(image: input)

        // Then
        #expect(ImageDecompression.isDecompressionNeeded(for: output) != true)
    }

    @Test func grayscalePreserved() throws {
        // Given
        let input = Test.image(named: "grayscale", extension: "jpeg")
        #expect(input.cgImage?.bitsPerComponent == 8)
        #expect(input.cgImage?.bitsPerPixel == 8)

        // When
        let output = ImageDecompression.decompress(image: input, isUsingPrepareForDisplay: true)

        // Then
        #expect(output.cgImage?.bitsPerPixel == 8)
        #expect(output.cgImage?.bitsPerComponent == 8)
    }
}

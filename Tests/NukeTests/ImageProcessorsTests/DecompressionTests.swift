// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke

@Suite struct ImageDecompressionTests {

    @Test func decompressionNotNeededFlagSet() throws {
        // Given
        let input = Test.image
        ImageDecompression.setDecompressionNeeded(true, for: input)

        // When
        let output = ImageDecompression.decompress(image: input)

        // Then
        #expect(ImageDecompression.isDecompressionNeeded(for: output) == nil)
    }

    @Test func grayscalePreserved() throws {
        // Given
        let input = Test.image(named: "grayscale", extension: "jpeg")
        #expect(input.cgImage?.bitsPerComponent == 8)
        #expect(input.cgImage?.bitsPerPixel == 8)

        // When
        let output = ImageDecompression.decompress(image: input, isUsingPrepareForDisplay: true)

        // Then
        // The original image doesn't have an alpha channel (kCGImageAlphaNone),
        // but this parameter combination (8 bbc and kCGImageAlphaNone) is not
        // supported by CGContext. Thus we are switching to a different format.
#if os(iOS) || os(tvOS) || os(visionOS)
        if #available(iOS 15.0, tvOS 15.0, *) {
            #expect(output.cgImage?.bitsPerPixel == 8) // Yay, preparingForDisplay supports it // Yay, preparingForDisplay supports it
            #expect(output.cgImage?.bitsPerComponent == 8)
        } else {
            #expect(output.cgImage?.bitsPerPixel == 8)
            #expect(output.cgImage?.bitsPerComponent == 8)
        }
#else
        #expect(output.cgImage?.bitsPerPixel == 8)
        #expect(output.cgImage?.bitsPerComponent == 8)
#endif
    }
}

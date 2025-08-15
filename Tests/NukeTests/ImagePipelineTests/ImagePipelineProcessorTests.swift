// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

#if !os(macOS)
import UIKit
#endif

@Suite struct ImagePipelineProcessorTests {
    var mockDataLoader: MockDataLoader!
    var pipeline: ImagePipeline!

    init() {
        mockDataLoader = MockDataLoader()
        pipeline = ImagePipeline {
            $0.dataLoader = mockDataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Applying Filters

    @Test func thatImageIsProcessed() async throws {
        // Given
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "processor1")])

        // When
        let image = try await pipeline.image(for: request)

        // Then
        #expect(image.nk_test_processorIDs == ["processor1"])
    }

    // MARK: - Composing Filters

    @Test func applyingMultipleProcessors() async throws {
        // Given
        let request = ImageRequest(
            url: Test.url,
            processors: [
                MockImageProcessor(id: "processor1"),
                MockImageProcessor(id: "processor2")
            ]
        )

        // When
        let image = try await pipeline.image(for: request)

        // Then
        #expect(image.nk_test_processorIDs == ["processor1", "processor2"])
    }

    @Test func performingRequestWithoutProcessors() async throws {
        // Given
        let request = ImageRequest(url: Test.url, processors: [])

        // When
        let image = try await pipeline.image(for: request)

        // Then
        #expect(image.nk_test_processorIDs == [])
    }

    // MARK: - Decompression

#if !os(macOS)
    @Test func decompressionSkippedIfProcessorsAreApplied() async throws {
        // Given
        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { image in
            #expect(ImageDecompression.isDecompressionNeeded(for: image) == true)
            return image
        })])

        // When
        _ = try await pipeline.image(for: request)
    }
#endif
}

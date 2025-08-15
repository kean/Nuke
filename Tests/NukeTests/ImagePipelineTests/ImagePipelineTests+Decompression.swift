// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke

#if canImport(UIKit)

extension ImagePipelineTests {
    @Test func disablingDecompression() async throws {
        // Given
        pipeline = pipeline.reconfigured {
            $0.isDecompressionEnabled = false
        }

        // When
        let image = try await pipeline.image(for: Test.url)

        // Then
        #expect(true == ImageDecompression.isDecompressionNeeded(for: image))
    }

    @Test func disablingDecompressionForIndividualRequest() async throws {
        // Given
        let request = ImageRequest(url: Test.url, options: [.skipDecompression])

        // When
        let image = try await pipeline.image(for: request)

        // Then
        #expect(true == ImageDecompression.isDecompressionNeeded(for: image))
    }

    @Test func decompressionPerformed() async throws {
        // When
        let image = try await pipeline.image(for: Test.request)

        // Then
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
    }

    @Test func decompressionNotPerformedWhenProcessorWasApplied() async throws {
        // Given request with scaling processor
        let input = Test.image
        pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in MockAnonymousImageDecoder(output: input) }
        }

        let request = ImageRequest(url: Test.url, processors: [
            .resize(size: CGSize(width: 40, height: 40))
        ])

        // When
        _ = try await pipeline.image(for: request)

        // Then
        #expect(true == ImageDecompression.isDecompressionNeeded(for: input))
    }

    @Test func decompressionPerformedWhenProcessorIsAppliedButDoesNothing() async throws {
        // Given request with scaling processor
        let request = ImageRequest(url: Test.url, processors: [MockEmptyImageProcessor()])

        // When
        let image = try await pipeline.image(for: request)

        // Them decompression to be performed (processor is applied but it did nothing)
        #expect(ImageDecompression.isDecompressionNeeded(for: image) == nil)
    }
}

#endif

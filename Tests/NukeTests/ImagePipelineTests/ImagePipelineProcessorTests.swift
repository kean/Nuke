// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

#if !os(macOS)
import UIKit
#endif

@Suite(.timeLimit(.minutes(1)))
struct ImagePipelineProcessorTests {
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    // MARK: - Applying Filters

    @Test func thatImageIsProcessed() async throws {
        // Given
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "processor1")])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == ["processor1"])
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
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == ["processor1", "processor2"])
    }

    @Test func performingRequestWithoutProcessors() async throws {
        // Given
        let request = ImageRequest(url: Test.url, processors: [])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.nk_test_processorIDs == [])
    }

    // MARK: - Processor Failures

    @Test func processorFailurePropagatesAsError() async throws {
        // GIVEN a request with a processor that always returns nil
        let request = ImageRequest(url: Test.url, processors: [MockFailingProcessor()])

        // WHEN
        do {
            _ = try await pipeline.imageTask(with: request).response
            Issue.record("Expected processing error")
        } catch {
            // THEN the pipeline surfaces a processingFailed error
            if case .processingFailed = error {
                // Expected
            } else {
                Issue.record("Expected processingFailed, got \(error)")
            }
        }
    }

    @Test func firstProcessorSucceedsSecondFails() async throws {
        // GIVEN a request where only the second processor fails
        let request = ImageRequest(url: Test.url, processors: [
            MockImageProcessor(id: "ok"),
            MockFailingProcessor()
        ])

        // WHEN/THEN the error still surfaces even after the first processor succeeds
        do {
            _ = try await pipeline.imageTask(with: request).response
            Issue.record("Expected processing error")
        } catch {
            if case .processingFailed = error {
                // Expected
            } else {
                Issue.record("Expected processingFailed, got \(error)")
            }
        }
    }

    // MARK: - Decompression

#if !os(macOS)
    @Test func decompressionSkippedIfProcessorsAreApplied() async throws {
        // Given
        let request = ImageRequest(url: Test.url, processors: [ImageProcessors.Anonymous(id: "1", { image in
            #expect(ImageDecompression.isDecompressionNeeded(for: image) == true)
            return image
        })])

        // When/Then
        _ = try await pipeline.image(for: request)
    }
#endif
}

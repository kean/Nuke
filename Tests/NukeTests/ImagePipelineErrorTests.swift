// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineErrorTests {

    // MARK: - isCancelled

    @Test func isCancelledReturnsTrueForCancelled() {
        #expect(ImagePipeline.Error.cancelled.isCancelled)
    }

    @Test func isCancelledReturnsFalseForOtherCases() {
        let cases: [ImagePipeline.Error] = [
            .dataMissingInCache,
            .dataLoadingFailed(error: URLError(.notConnectedToInternet)),
            .dataIsEmpty,
            .imageRequestMissing,
            .pipelineInvalidated,
            .dataDownloadExceededMaximumSize,
        ]
        for error in cases {
            #expect(!error.isCancelled)
        }
    }

    // MARK: - dataLoadingError

    @Test func dataLoadingErrorReturnsUnderlyingError() {
        let underlying = URLError(.notConnectedToInternet)
        let error = ImagePipeline.Error.dataLoadingFailed(error: underlying)

        let result = error.dataLoadingError as? URLError
        #expect(result?.code == .notConnectedToInternet)
    }

    @Test func dataLoadingErrorReturnsNilForOtherCases() {
        let cases: [ImagePipeline.Error] = [
            .dataMissingInCache,
            .dataIsEmpty,
            .imageRequestMissing,
            .pipelineInvalidated,
            .dataDownloadExceededMaximumSize,
            .cancelled,
        ]
        for error in cases {
            #expect(error.dataLoadingError == nil)
        }
    }

    // MARK: - Descriptions

    @Test func dataMissingInCacheDescription() {
        let error = ImagePipeline.Error.dataMissingInCache
        #expect(error.description.contains("cache"))
    }

    @Test func dataLoadingFailedDescription() {
        let underlying = URLError(.timedOut)
        let error = ImagePipeline.Error.dataLoadingFailed(error: underlying)
        #expect(error.description.contains("Failed to load image data"))
    }

    @Test func dataIsEmptyDescription() {
        let error = ImagePipeline.Error.dataIsEmpty
        #expect(error.description.contains("empty"))
    }

    @Test func decoderNotRegisteredDescription() {
        let error = ImagePipeline.Error.decoderNotRegistered(context: .mock)
        #expect(error.description.contains("No decoders"))
    }

    @Test func decodingFailedWithImageDecodingError() {
        let decoder = ImageDecoders.Default()
        let error = ImagePipeline.Error.decodingFailed(
            decoder: decoder,
            context: .mock,
            error: ImageDecodingError.unknown
        )
        // Should NOT contain "Underlying error" for ImageDecodingError
        #expect(!error.description.contains("Underlying error"))
        #expect(error.description.contains("Failed to decode"))
    }

    @Test func decodingFailedWithCustomError() {
        struct CustomError: Error {}
        let decoder = ImageDecoders.Default()
        let error = ImagePipeline.Error.decodingFailed(
            decoder: decoder,
            context: .mock,
            error: CustomError()
        )
        // Should contain "Underlying error" for non-ImageDecodingError
        #expect(error.description.contains("Underlying error"))
    }

    @Test func processingFailedWithImageProcessingError() {
        let processor = ImageProcessors.Resize(width: 100)
        let error = ImagePipeline.Error.processingFailed(
            processor: processor,
            context: .mock,
            error: ImageProcessingError.unknown
        )
        // Should NOT contain "Underlying error" for ImageProcessingError
        #expect(!error.description.contains("Underlying error"))
        #expect(error.description.contains("Failed to process"))
    }

    @Test func processingFailedWithCustomError() {
        struct CustomError: Error {}
        let processor = ImageProcessors.Resize(width: 100)
        let error = ImagePipeline.Error.processingFailed(
            processor: processor,
            context: .mock,
            error: CustomError()
        )
        #expect(error.description.contains("Underlying error"))
    }

    @Test func imageRequestMissingDescription() {
        let error = ImagePipeline.Error.imageRequestMissing
        #expect(error.description.contains("no image request"))
    }

    @Test func pipelineInvalidatedDescription() {
        let error = ImagePipeline.Error.pipelineInvalidated
        #expect(error.description.contains("invalidated"))
    }

    @Test func dataDownloadExceededMaximumSizeDescription() {
        let error = ImagePipeline.Error.dataDownloadExceededMaximumSize
        #expect(error.description.contains("exceeded"))
    }

    @Test func cancelledDescription() {
        #expect(ImagePipeline.Error.cancelled.description == "The image task was cancelled.")
    }

    // MARK: - Every Case

    /// One value of every case.
    static var allCases: [ImagePipeline.Error] {
        [
            .dataMissingInCache,
            .dataLoadingFailed(error: URLError(.timedOut)),
            .dataIsEmpty,
            .decoderNotRegistered(context: .mock),
            .decodingFailed(decoder: ImageDecoders.Default(), context: .mock, error: ImageDecodingError.unknown),
            .processingFailed(processor: ImageProcessors.Resize(width: 100), context: .mock, error: ImageProcessingError.unknown),
            .imageRequestMissing,
            .pipelineInvalidated,
            .dataDownloadExceededMaximumSize,
            .cancelled
        ]
    }

    @Test func onlyCancelledCaseIsCancelled() {
        let cancelled = Self.allCases.filter(\.isCancelled)
        #expect(cancelled.count == 1)
        #expect(cancelled.first?.description == ImagePipeline.Error.cancelled.description)
    }

    @Test func onlyDataLoadingFailedCaseHasDataLoadingError() {
        let withError = Self.allCases.filter { $0.dataLoadingError != nil }
        #expect(withError.count == 1)
        #expect((withError.first?.dataLoadingError as? URLError)?.code == .timedOut)
    }

    /// Distinct messages, so that a log line tells which failure it was.
    @Test func everyCaseHasDistinctDescription() {
        let descriptions = Self.allCases.map(\.description)
        #expect(descriptions.allSatisfy { !$0.isEmpty })
        #expect(Set(descriptions).count == descriptions.count)
    }

    /// The error is `Sendable` and travels through `Result` and task events,
    /// so the cases carrying a large context are boxed to keep it one word.
    @Test func errorIsOneWord() {
        #expect(MemoryLayout<ImagePipeline.Error>.size == MemoryLayout<Int>.size)
    }

    // MARK: - Underlying Errors in Descriptions

    @Test func dataLoadingFailedDescriptionIncludesUnderlyingError() {
        let underlying = MockError(description: "connection-reset-42")
        let error = ImagePipeline.Error.dataLoadingFailed(error: underlying)
        #expect(error.description.contains("connection-reset-42"))
    }

    @Test func decodingFailedDescriptionNamesDecoderAndUnderlyingError() {
        // Given
        let decoder = MockImageDecoder(name: "test")
        let error = ImagePipeline.Error.decodingFailed(
            decoder: decoder,
            context: .mock,
            error: MockError(description: "truncated-header")
        )

        // Then the decoder is named by its type
        #expect(error.description.contains("MockImageDecoder"))
        #expect(error.description.contains("truncated-header"))
    }

    @Test func processingFailedDescriptionNamesProcessorAndUnderlyingError() {
        // Given
        let processor = MockImageProcessor(id: "processor-9")
        let error = ImagePipeline.Error.processingFailed(
            processor: processor,
            context: .mock,
            error: MockError(description: "out-of-memory")
        )

        // Then
        #expect(error.description.contains("MockImageProcessor(id: processor-9)"))
        #expect(error.description.contains("out-of-memory"))
    }

    // MARK: - Context

    @Test func decodingFailedKeepsItsContext() throws {
        // Given
        let request = ImageRequest(url: Test.url).with { $0.imageID = "decoding-context" }
        let context = ImageDecodingContext(request: request, data: Data([0x01, 0x02]), isCompleted: true)

        // When
        let error = ImagePipeline.Error.decodingFailed(decoder: ImageDecoders.Default(), context: context, error: ImageDecodingError.unknown)

        // Then the boxed context comes back out intact
        guard case let .decodingFailed(_, unboxed, _) = error else {
            Issue.record("Unexpected case")
            return
        }
        #expect(unboxed.request.imageID == "decoding-context")
        #expect(unboxed.data == Data([0x01, 0x02]))
        #expect(unboxed.isCompleted)
    }
}

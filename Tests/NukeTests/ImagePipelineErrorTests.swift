// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineErrorTests {

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
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineErrorTests {

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

    @Test func processingFailedDescriptionIsExact() {
        // Given
        let processor = ImageProcessors.Resize(width: 100, unit: .pixels)
        let error = ImagePipeline.Error.processingFailed(processor: processor, context: .mock, error: MockError(description: "processing-failed"))

        // Then the message names the processor and the underlying error, and
        // it's what string interpolation produces
        let expected = "Failed to process the image using processor Resize(size: (100.0, 9999.0) pixels, contentMode: .aspectFit, crop: false, upscale: false). Underlying error: MockError(description: \"processing-failed\"). Image URL: \(Test.url.absoluteString)."
        #expect(error.description == expected)
        #expect("\(error)" == expected)
    }

    @Test func localizedDescriptionIsTheDescription() {
        let error: any Error = ImagePipeline.Error.dataIsEmpty
        #expect(error.localizedDescription == "Data loader returned empty data.")
    }

    @Test func localizedDescriptionOfWrappedDataLoaderError() {
        let error: any Error = ImagePipeline.Error.dataLoadingFailed(error: DataLoader.Error.statusCodeUnacceptable(404))
        #expect(error.localizedDescription == "Failed to load image data. Underlying error: Response status code was unacceptable: 404.")
    }

    // MARK: - What Was Received

    /// A server that answers `200` with an error page is the most common way
    /// to end up with a broken image. The message has to say so.
    @Test func decodingFailedDescriptionShowsWhatWasReceived() {
        let url = URL(string: "https://example.com/image.jpeg")!
        let response = HTTPURLResponse(url: url, mimeType: "text/html", expectedContentLength: 2048, textEncodingName: nil)
        let context = ImageDecodingContext(request: ImageRequest(url: url), data: Data("<!DOCTYPE html>\n<html><body>Not Found</body></html>".utf8), urlResponse: response)

        let error = ImagePipeline.Error.decodingFailed(decoder: ImageDecoders.Default(), context: context, error: ImageDecodingError.unknown)

        #expect(error.description.contains("of text/html"))
        #expect(error.description.contains("from https://example.com/image.jpeg"))
        #expect(error.description.contains(#"starting with "<!DOCTYPE html> <html><body>Not""#))
    }

    @Test func decoderNotRegisteredDescriptionShowsWhatWasReceived() {
        let context = ImageDecodingContext.mock(data: Data("not an image".utf8))

        let error = ImagePipeline.Error.decoderNotRegistered(context: context)

        #expect(error.description.hasPrefix("No decoders registered for the downloaded data. Received 12 bytes from "))
        #expect(error.description.hasSuffix(#", starting with "not an image"."#))
    }

    @Test func descriptionShowsStatusCode() {
        let url = URL(string: "https://example.com/image.jpeg")!
        let response = HTTPURLResponse(url: url, statusCode: 203, httpVersion: nil, headerFields: nil)
        let context = ImageDecodingContext(request: ImageRequest(url: url), data: Data("x".utf8), urlResponse: response)

        #expect(ImagePipeline.Error.decoderNotRegistered(context: context).description.contains("(HTTP 203)"))
    }

    @Test func descriptionNamesRecognizedFormat() {
        let context = ImageDecodingContext.mock(data: Test.data)

        // The data decides, not the response, which can be wrong.
        #expect(ImagePipeline.Error.decoderNotRegistered(context: context).description.contains(" of jpeg from "))
    }

    @Test func descriptionPrintsBinaryDataAsHex() {
        let context = ImageDecodingContext.mock(data: Data([0x00, 0x01, 0xFE, 0xFF, 0x10, 0x20, 0x30, 0x40, 0x50]))

        let description = ImagePipeline.Error.decoderNotRegistered(context: context).description

        #expect(description.hasSuffix(", starting with 00 01 fe ff 10 20 30 40."))
    }

    @Test(arguments: [
        ("https://example.com/a.jpeg?token=secret#fragment", "https://example.com/a.jpeg?…"),
        ("https://user:password@example.com/a.jpeg", "https://example.com/a.jpeg"),
        ("https://example.com/a.jpeg", "https://example.com/a.jpeg"),
        ("data:image/png;base64,iVBORw0KGgo=", "data:…")
    ])
    func descriptionRedactsURL(input: String, expected: String) throws {
        let request = ImageRequest(url: URL(string: input))
        let context = ImageDecodingContext(request: request, data: Data("x".utf8))

        let description = ImagePipeline.Error.decoderNotRegistered(context: context).description

        #expect(description.contains(" from \(expected), "))
        #expect(!description.contains("secret"))
        #expect(!description.contains("password"))
        #expect(!description.contains("iVBORw0KGgo"))
    }

    @Test func processingFailedDescriptionRedactsURL() {
        let request = ImageRequest(url: URL(string: "https://example.com/a.jpeg?token=secret"))
        let context = ImageProcessingContext(request: request, response: Test.response, isCompleted: true)

        let error = ImagePipeline.Error.processingFailed(processor: ImageProcessors.Resize(width: 100), context: context, error: ImageProcessingError.unknown)

        #expect(error.description.hasSuffix(" Image URL: https://example.com/a.jpeg?…."))
    }

    @Test func pipelineReportsTheErrorPageItReceived() async throws {
        let url = URL(string: "https://example.com/image.jpeg")!
        let dataLoader = MockDataLoader()
        let response = HTTPURLResponse(url: url, mimeType: "text/html", expectedContentLength: -1, textEncodingName: nil)
        dataLoader.results[url] = .success((Data("<html>Oops</html>".utf8), response))
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataCache = nil
        }

        await #expect {
            _ = try await pipeline.image(for: url)
        } throws: { error in
            let description = "\(error)"
            return description.contains("text/html") && description.contains(#""<html>Oops</html>""#)
        }
    }
}

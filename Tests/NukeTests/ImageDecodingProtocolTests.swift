// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@_spi(AsyncImageDecoding) @testable import Nuke

/// Covers the ``ImageDecoding`` defaults and the step that turns a decoding
/// context into an ``ImageResponse`` – the one the pipeline takes for every
/// decoder, built-in or not.
@Suite(.timeLimit(.minutes(5)))
struct ImageDecodingProtocolTests {

    // MARK: Defaults

    @Test func aDecoderThatOnlyDecodesIsAsynchronousAndHasNoPreviews() {
        let decoder = ProtocolDefaultsDecoder()

        #expect(decoder.isAsynchronous)
        #expect(decoder.decodePartiallyDownloadedData(Test.data) == nil)
    }

    @Test func contextDefaults() {
        let context = ImageDecodingContext(request: Test.request, data: Test.data)

        #expect(context.data == Test.data)
        #expect(context.isCompleted)
        #expect(context.urlResponse == nil)
        #expect(context.cacheType == nil)
        #expect(context.previewPolicy == .incremental)
        #expect(context.isAnimatedImageParsingEnabled)
    }

    @Test func errorDescriptions() {
        #expect(ImageDecodingError.unknown.description == "Unknown")
        #expect(ImageDecodingError.synchronousDecodingUnsupported.description == "Synchronous decoding is not supported")
    }

    // MARK: Decoding a Context

    @Test func completedContextProducesAResponseWithTheContextMetadata() throws {
        // Given
        let context = ImageDecodingContext(
            request: Test.request,
            data: Test.data,
            isCompleted: true,
            urlResponse: Test.urlResponse,
            cacheType: .disk
        )

        // When
        let response = try ImageDecoders.Default().decode(context)

        // Then
        #expect(response.container.type == .jpeg)
        #expect(!response.container.isPreview)
        #expect(response.request.url == Test.url)
        #expect(response.urlResponse === Test.urlResponse)
        #expect(response.cacheType == .disk)
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 480))
    }

    @Test func completedContextNeverAsksForAPreview() throws {
        let decoder = RoutingRecordingDecoder(preview: ImageContainer(image: PlatformImage(), isPreview: true))

        let response = try decoder.decode(ImageDecodingContext(request: Test.request, data: Test.data, isCompleted: true))

        #expect(!response.container.isPreview)
        #expect(decoder.calls == ["decode"])
    }

    @Test func incompleteContextProducesAPreviewResponse() throws {
        let data = Test.data(name: "progressive", extension: "jpeg")
        let context = ImageDecodingContext(request: Test.request, data: data[0..<5000], isCompleted: false)

        let response = try ImageDecoders.Default().decode(context)

        #expect(response.container.isPreview)
        #expect(response.container.userInfo[.scanNumberKey] as? Int == 1)
    }

    @Test func incompleteContextWithNoPreviewThrowsWithoutDecodingTheData() {
        // The partial data must never reach `decode(_:)`: a decoder that can
        // read a truncated file would hand back a final image that isn't one.
        let decoder = RoutingRecordingDecoder(preview: nil)

        #expect(throws: ImageDecodingError.unknown) {
            try decoder.decode(ImageDecodingContext(request: Test.request, data: Test.data, isCompleted: false))
        }
        #expect(decoder.calls == ["preview"])
    }

    @Test func errorsThrownByTheDecoderPropagateUnchanged() {
        #expect(throws: MockError(description: "decoder-failed")) {
            try MockFailingDecoder().decode(ImageDecodingContext(request: Test.request, data: Test.data))
        }
    }

    // MARK: Async Decoders

    @Test func asyncDecoderDecodesACompletedContext() async throws {
        let context = ImageDecodingContext(request: Test.request, data: Test.data, urlResponse: Test.urlResponse, cacheType: .memory)

        let response = try await RoutingAsyncDecoder(preview: nil).decode(context)

        #expect(!response.container.isPreview)
        #expect(response.urlResponse === Test.urlResponse)
        #expect(response.cacheType == .memory)
    }

    @Test func asyncDecoderProducesAPreviewForAnIncompleteContext() async throws {
        let decoder = RoutingAsyncDecoder(preview: ImageContainer(image: PlatformImage(), isPreview: true))

        let response = try await decoder.decode(ImageDecodingContext(request: Test.request, data: Test.data, isCompleted: false))

        #expect(response.container.isPreview)
    }

    @Test func asyncDecoderThrowsForAnIncompleteContextWithNoPreview() async {
        let decoder = RoutingAsyncDecoder(preview: nil)

        await #expect(throws: ImageDecodingError.unknown) {
            try await decoder.decode(ImageDecodingContext(request: Test.request, data: Test.data, isCompleted: false))
        }
    }

    // MARK: Decompression

    @Test func onlyAFullSizeFinalImageIsMarkedForDecompression() throws {
        // A preview is replaced within moments, and a thumbnail comes out of
        // Image I/O already decoded, so decompressing either is wasted work.
        let progressive = Test.data(name: "progressive", extension: "jpeg")
        var thumbnailRequest = Test.request
        thumbnailRequest.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 64)

        let final = try ImageDecoders.Default().decode(ImageDecodingContext(request: Test.request, data: Test.data))
        let preview = try ImageDecoders.Default().decode(ImageDecodingContext(request: Test.request, data: progressive[0..<5000], isCompleted: false))
        let thumbnailContext = ImageDecodingContext(request: thumbnailRequest, data: Test.data)
        let thumbnail = try #require(ImageDecoders.Default(context: thumbnailContext)).decode(thumbnailContext)

        #expect(ImageDecompression.isDecompressionNeeded(for: final.image) == true)
        #expect(ImageDecompression.isDecompressionNeeded(for: preview.image) == nil)
        #expect(ImageDecompression.isDecompressionNeeded(for: thumbnail.image) == nil)
    }
}

// MARK: - Helpers

/// Implements the one requirement a decoder can't do without.
private struct ProtocolDefaultsDecoder: ImageDecoding {
    func decode(_ data: Data) throws -> ImageContainer {
        ImageContainer(image: PlatformImage())
    }
}

/// Records which of the two decoding methods the context was routed to.
private final class RoutingRecordingDecoder: ImageDecoding, @unchecked Sendable {
    private let preview: ImageContainer?
    private let lock = NSLock()
    private var _calls: [String] = []

    var calls: [String] { lock.withLock { _calls } }

    init(preview: ImageContainer?) {
        self.preview = preview
    }

    func decode(_ data: Data) throws -> ImageContainer {
        lock.withLock { _calls.append("decode") }
        return ImageContainer(image: PlatformImage())
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        lock.withLock { _calls.append("preview") }
        return preview
    }
}

private final class RoutingAsyncDecoder: AsyncImageDecoding, @unchecked Sendable {
    private let preview: ImageContainer?

    init(preview: ImageContainer?) {
        self.preview = preview
    }

    func decode(_ data: Data) async throws -> ImageContainer {
        await Task.yield()
        return ImageContainer(image: PlatformImage())
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        preview
    }
}

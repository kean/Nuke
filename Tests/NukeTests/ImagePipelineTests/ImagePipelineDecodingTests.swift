// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@_spi(AsyncImageDecoding) @testable import Nuke

import UniformTypeIdentifiers


@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDecodingTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func experimentalDecoder() async throws {
        // Given
        let dummyData = "123".data(using: .utf8)
        let decoder = MockScriptedDecoder { _ in
            ImageContainer(image: PlatformImage(), data: dummyData, userInfo: ["a": 1])
        }

        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }

        // When
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then
        let container = response.container
        #expect(container.data == dummyData)
        #expect(container.userInfo["a"] as? Int == 1)
    }

    @Test func asyncDecoder() async throws {
        // Given
        let expectedData = Data("async-decoder".utf8)
        let decoder = MockAsyncDecoder { _ in
            await Task.yield()
            return ImageContainer(image: PlatformImage(), data: expectedData)
        }

        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }

        // When
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then
        #expect(response.container.data == expectedData)
    }

    // MARK: - Decoder Errors

    @Test func decoderErrorIsWrapped() async {
        // Given
        let decoder = MockFailingDecoder()
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }

        // When/Then
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            if case let .decodingFailed(failedDecoder, context, error) = error {
                #expect((failedDecoder as? MockFailingDecoder) === decoder)
                #expect(context.request.url == Test.request.url)
                #expect(context.data == Test.data)
                #expect(context.isCompleted)
                #expect(context.urlResponse?.url == Test.url)
                #expect(error as? MockError == MockError(description: "decoder-failed"))
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test func missingDecoderFailsWithDecoderNotRegistered() async {
        // Given a pipeline where no decoder can handle the data
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in nil }
        }

        // When/Then
        do {
            _ = try await pipeline.image(for: Test.request)
            Issue.record("Expected failure")
        } catch {
            guard case let .decoderNotRegistered(context) = error else {
                Issue.record("Expected .decoderNotRegistered")
                return
            }
            #expect(context.request.url == Test.request.url)
            #expect(context.data.count == 22789)
            #expect(context.isCompleted)
            #expect(context.urlResponse?.url == Test.url)
        }
    }

    @Test func asyncDecoderErrorIsWrapped() async throws {
        // Given
        let expectedError = MockError(description: "async-decoder-failed")
        let decoder = MockAsyncDecoder { _ in
            await Task.yield()
            throw expectedError
        }

        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }

        // When
        do {
            _ = try await pipeline.imageTask(with: Test.request).response
            Issue.record("Expected a decoding error")
        } catch {
            // Then
            guard case let .decodingFailed(failedDecoder, context, underlyingError) = error else {
                Issue.record("Expected decodingFailed, got \(error)")
                return
            }
            #expect((failedDecoder as? MockAsyncDecoder) === decoder)
            #expect(context.data == Test.data)
            #expect(underlyingError as? MockError == expectedError)
        }
    }

    // MARK: - Async Decoders (Previews)

    /// An async decoder is never asked to decode synchronously – the default
    /// implementation of the synchronous requirement always throws.
    @Test func asyncDecoderRejectsSynchronousDecoding() throws {
        // Given
        let decoder: any ImageDecoding = MockAsyncDecoder { _ in ImageContainer(image: PlatformImage()) }

        // When/Then
        do {
            _ = try decoder.decode(Test.data)
            Issue.record("Expected the decoder to throw")
        } catch {
            #expect(error as? ImageDecodingError == .synchronousDecodingUnsupported)
        }
    }

    @Test func asyncDecoderProducesPreviews() async throws {
        // Given a decoder that supports progressive decoding
        let dataLoader = MockProgressiveDataLoader()
        let decoder = MockAsyncDecoder { _ in
            ImageContainer(image: Test.image)
        } decodePreview: { _ in
            ImageContainer(image: Test.image, isPreview: true)
        }
        let pipeline = dataLoader.makePipeline {
            $0.makeImageDecoder = { _ in decoder }
        }

        // When
        var previewCount = 0
        let task = pipeline.imageTask(with: Test.request)
        for await event in task.events {
            switch event {
            case .preview:
                previewCount += 1
                dataLoader.resume()
            default:
                break
            }
        }

        // Then
        #expect(previewCount > 0)
        #expect(try await task.response.container.isPreview == false)
    }

    /// When an async decoder doesn't support progressive decoding, the partial
    /// data is discarded and no previews are produced.
    @Test func asyncDecoderWithoutPreviewSupportProducesNoPreviews() async throws {
        // Given
        let dataLoader = MockProgressiveDataLoader()
        let decoder = MockAsyncDecoder { _ in
            ImageContainer(image: Test.image)
        }
        let pipeline = dataLoader.makePipeline {
            $0.makeImageDecoder = { _ in decoder }
        }

        // When
        var previewCount = 0
        let task = pipeline.imageTask(with: Test.request)
        for await event in task.events {
            switch event {
            case .preview:
                previewCount += 1
            case .progress:
                dataLoader.resume()
            default:
                break
            }
        }

        // Then the request still succeeds
        #expect(previewCount == 0)
        _ = try await task.response
    }
}

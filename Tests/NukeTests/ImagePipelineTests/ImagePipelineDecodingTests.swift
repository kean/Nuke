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

    // MARK: - Animated Images

    /// Parsing an animation takes as long as the file has frames. On the
    /// pipeline's actor, every image load in the process would wait for it.
    @Test(arguments: [("cat", "gif"), ("animated", "webp"), ("animated", "avif")])
    @ImagePipelineActor func animationIsParsedOnTheDecodingQueue(fixture: (name: String, extension: String)) async throws {
        // Given
        dataLoader.results[Test.url] = .success((Test.data(name: fixture.name, extension: fixture.extension), Test.urlResponse))
        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        // When
        let expectation = TestExpectation(queue: queue, count: 1)
        let task = pipeline.imageTask(with: Test.url)
        await expectation.wait(timeout: .seconds(5))

        // Then the task waits for the queue
        #expect(expectation.operations.count == 1)
        queue.isSuspended = false
        #expect(try await task.response.container.animation != nil)
    }

    /// The same parse runs again when a disk hit brings the image back, which
    /// is the common way to reach it in an app that scrolls through GIFs.
    @Test @ImagePipelineActor func animationFromDiskCacheIsParsedOnTheDecodingQueue() async throws {
        // Given
        let dataCache = MockDataCache()
        dataCache.store[Test.url.absoluteString] = Test.data(name: "cat", extension: "gif")
        let pipeline = pipeline.reconfigured { $0.dataCache = dataCache }
        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        // When
        let expectation = TestExpectation(queue: queue, count: 1)
        let task = pipeline.imageTask(with: Test.url)
        await expectation.wait(timeout: .seconds(5))

        // Then
        #expect(expectation.operations.count == 1)
        queue.isSuspended = false
        let response = try await task.response
        #expect(response.cacheType == .disk)
        #expect(response.container.animation != nil)
    }

    /// A still image costs little to decode, and a hop to the queue would be
    /// what it spends the most time on.
    @Test @ImagePipelineActor func stillImageSkipsTheDecodingQueue() async throws {
        // Given
        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        // When
        let response = try await pipeline.imageTask(with: Test.url).response

        // Then
        #expect(response.container.type == .jpeg)
        #expect(queue.operationCount == 0)
    }

    /// The decision is per decode because the decoder of a progressive download
    /// is created from the first chunk, and a preview has to stay synchronous:
    /// otherwise the final decode overtakes it.
    @Test func onlyTheFinalDecodeOfAnAnimationLeavesTheActor() throws {
        // Given
        let gif = Test.data(name: "cat", extension: "gif")
        let decoder = try #require(ImageDecoders.Default(context: .mock(data: gif.prefix(1000), isCompleted: false)))

        // Then
        #expect(!decoder.parsesAnimation(in: .mock(data: gif.prefix(1000), isCompleted: false)))
        #expect(decoder.parsesAnimation(in: .mock(data: gif)))
    }

    @Test func thumbnailOfAnAnimationParsesNothing() throws {
        // Given
        let gif = Test.data(name: "cat", extension: "gif")
        let request = ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 100) }
        let context = ImageDecodingContext(request: request, data: gif)
        let decoder = try #require(ImageDecoders.Default(context: context))

        // Then it's on the queue, where it's already asynchronous
        #expect(decoder.isAsynchronous)
        #expect(!decoder.parsesAnimation(in: context))
    }

    /// Every completed decode asks, so the answer has to come from a header.
    @Test(arguments: [
        ("fixture", "jpeg", false), ("fixture", "png", false), ("baseline", "webp", false), ("img_751", "heic", false),
        ("cat", "gif", true), ("animated", "webp", true), ("animated", "avif", true)
    ]) func parsesAnimationOnlyWhenTheDataHoldsOne(fixture: (name: String, extension: String, isAnimated: Bool)) throws {
        // Given
        let data = Test.data(name: fixture.name, extension: fixture.extension)
        let decoder = ImageDecoders.Default()

        // Then
        #expect(decoder.parsesAnimation(in: .mock(data: data)) == fixture.isAnimated)
    }

    @Test @ImagePipelineActor func animationSkipsTheDecodingQueueWhenParsingIsDisabled() async throws {
        // Given
        dataLoader.results[Test.url] = .success((Test.data(name: "cat", extension: "gif"), Test.urlResponse))
        let pipeline = pipeline.reconfigured { $0.isAnimatedImageParsingEnabled = false }
        let queue = pipeline.configuration.imageDecodingQueue
        queue.isSuspended = true

        // When
        let response = try await pipeline.imageTask(with: Test.url).response

        // Then
        #expect(response.container.animation == nil)
        #expect(queue.operationCount == 0)
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
            case .progress:
                // Serve the next chunk on progress rather than on a preview: the
                // pipeline drops a preview while the previous one is still being
                // decoded, and the loader would stall waiting for it.
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

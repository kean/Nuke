// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Covers the decompression stage of `TaskLoadImage` through the delegate
/// hooks that control it.
///
/// The images are decoded with a decoder that marks them as needing
/// decompression – what the default decoder does on every platform but macOS
/// – so the stage runs the same way everywhere.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDecompressionStageTests {
    private let dataLoader: MockDataLoader
    private let imageCache: MockImageCache
    private let delegate: DecompressionRecordingDelegate
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        let imageCache = MockImageCache()
        let delegate = DecompressionRecordingDelegate()
        self.dataLoader = dataLoader
        self.imageCache = imageCache
        self.delegate = delegate
        self.pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
            $0.isDecompressionEnabled = true
            $0.makeImageDecoder = { DecompressionFlaggingDecoder(context: $0) }
        }
    }

    // MARK: - Delegate

    @Test func responseReturnedByTheDelegateIsDeliveredAndCached() async throws {
        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(response.container.userInfo[.isDecompressedKey] as? Bool == true)
        #expect(ImageDecompression.isDecompressionNeeded(for: response.image) == nil)
        #expect(imageCache[Test.request]?.image === response.image)
        #expect(delegate.decompressedResponses.count == 1)
        #expect(delegate.decompressedRequests.first?.url == Test.url)
    }

    // MARK: - Processing

    /// Neither the original image the processors are applied to, nor the new
    /// image they produce is decompressed.
    @Test func processedImagesAreNotDecompressed() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: [MockImageProcessor(id: "1")])

        // WHEN
        _ = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(delegate.consultedResponses.isEmpty)
        #expect(delegate.decompressedResponses.isEmpty)
    }

    /// A processor can return the image it was given. The image is then
    /// decompressed for the request that has the processor, and not before.
    @Test func imageReturnedByAProcessorAsIsIsDecompressedOnce() async throws {
        // GIVEN
        let request = ImageRequest(url: Test.url, processors: [MockEmptyImageProcessor()])

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(delegate.decompressedResponses.count == 1)
        #expect(delegate.decompressedRequests.first?.processors.count == 1)
        #expect(response.container.userInfo[.isDecompressedKey] as? Bool == true)
    }

    // MARK: - Scheduling

    @Test @ImagePipelineActor func decompressionRunsOnTheDecompressingQueue() async throws {
        // GIVEN a suspended decompressing queue
        let queue = pipeline.configuration.imageDecompressingQueue
        queue.isSuspended = true

        // WHEN
        let expectation = TestExpectation(queue: queue, count: 1)
        let task = pipeline.imageTask(with: Test.request)
        await expectation.wait()

        // THEN the delegate is asked before the decompression is scheduled,
        // and the image is neither delivered nor cached before it is decompressed
        #expect(delegate.consultedResponses.count == 1)
        #expect(delegate.decompressedResponses.isEmpty)
        #expect(imageCache[Test.request] == nil)

        queue.isSuspended = false
        let response = try await task.response
        #expect(response.container.userInfo[.isDecompressedKey] as? Bool == true)
        #expect(delegate.decompressedResponses.count == 1)
    }

    @Test @ImagePipelineActor func cancellingTheTaskCancelsPendingDecompression() async throws {
        // GIVEN a decompression waiting in a suspended queue
        let queue = pipeline.configuration.imageDecompressingQueue
        queue.isSuspended = true
        let expectation = TestExpectation(queue: queue, count: 1)
        let task = pipeline.imageTask(with: Test.request)
        await expectation.wait()
        let operation = try #require(expectation.operations.first)

        // WHEN
        await queue.waitForCancellation(of: operation) {
            task.cancel()
        }

        // THEN
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }
        queue.isSuspended = false
        await queue.waitUntilAllOperationsAreFinished()
        #expect(delegate.decompressedResponses.isEmpty)
        #expect(imageCache[Test.request] == nil)
    }

    @Test @ImagePipelineActor func decompressionPriorityFollowsTheTask() async throws {
        // GIVEN a decompression waiting in a suspended queue
        let queue = pipeline.configuration.imageDecompressingQueue
        queue.isSuspended = true
        let expectation = TestExpectation(queue: queue, count: 1)
        let task = pipeline.imageTask(with: Test.request)
        await expectation.wait()
        let operation = try #require(expectation.operations.first)
        #expect(operation.priority == .normal)

        // WHEN/THEN
        await queue.waitForPriorityChange(of: operation, to: .high) {
            task.priority = .high
        }
        queue.isSuspended = false
        _ = try await task.response
    }

    @Test func decompressionIsRecordedInTheDiagnostics() async throws {
        // GIVEN
        let pipeline = pipeline.reconfiguredKeepingDelegate(delegate) {
            $0.isDiagnosticsEnabled = true
        }

        // WHEN
        let task = pipeline.imageTask(with: Test.request)
        _ = try await task.response

        // THEN
        let metrics = try #require(task.metrics)
        let stages = metrics.jobs[0].stages.filter { $0.kind == .decompress }
        #expect(stages.count == 1)
        let stage = try #require(stages.first)
        #expect(stage.isProgressive == false)
        #expect(stage.queuedAt != nil)
        #expect(stage.workDuration != nil)
        #expect(stage.pixels == .init(width: 640, height: 480))
    }

    @Test func coalescedTasksShareOneDecompression() async throws {
        // WHEN
        let (task1, task2) = await withSuspendedDataLoading(for: pipeline, expectedCount: 2) {
            (pipeline.imageTask(with: Test.request), pipeline.imageTask(with: Test.request))
        }
        let response1 = try await task1.response
        let response2 = try await task2.response

        // THEN
        #expect(response1.image === response2.image)
        #expect(delegate.decompressedResponses.count == 1)
        #expect(dataLoader.createdTaskCount == 1)
    }

    @Test func imageFromDiskCacheIsDecompressedAndKeepsItsCacheType() async throws {
        // GIVEN
        let dataCache = MockDataCache()
        dataCache.store[Test.url.absoluteString] = Test.data
        let pipeline = pipeline.reconfiguredKeepingDelegate(delegate) {
            $0.dataCache = dataCache
        }

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN
        #expect(response.cacheType == .disk)
        #expect(response.container.userInfo[.isDecompressedKey] as? Bool == true)
        #expect(dataLoader.createdTaskCount == 0)
    }

    // MARK: - Progressive Decoding

    /// Previews are dropped while the decompression of a previous one is still
    /// pending, and the final image cancels the pending one.
    @Test @ImagePipelineActor func previewsArrivingWhileDecompressionIsBusyAreDropped() async throws {
        // GIVEN a decoder that marks the previews as needing decompression too,
        // and a suspended decompressing queue
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isDecompressionEnabled = true
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.makeImageDecoder = { DecompressionFlaggingDecoder(context: $0, isFlaggingPreviews: true) }
        }
        let queue = pipeline.configuration.imageDecompressingQueue
        queue.isSuspended = true
        let expectation = TestExpectation(queue: queue, count: 2)

        // WHEN the whole image is downloaded while the first preview waits
        let events = LockedArray<ImageTask.Event>()
        let task = pipeline.makeStartedImageTask(with: Test.request) { event, _ in
            events.append(event)
            if case .progress = event {
                dataLoader.resume()
            }
        }
        await expectation.wait()
        queue.isSuspended = false
        let response = try await task.response

        // THEN only the first preview and the final image are scheduled, and
        // only the final image is decompressed and delivered
        #expect(expectation.operations.count == 2)
        #expect(expectation.operations.first?.isCancelled == true)
        #expect(delegate.decompressedResponses.map(\.isPreview) == [false])
        #expect(!events.values.contains { if case .preview = $0 { true } else { false } })
        #expect(response.container.userInfo[.isDecompressedKey] as? Bool == true)
    }

#if !os(macOS)
    @Test func defaultDecoderDoesNotOfferPreviewsForDecompression() async throws {
        // GIVEN the default decoder
        let dataLoader = MockProgressiveDataLoader()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }

        // WHEN
        let previews = LockedArray<ImageResponse>()
        let task = pipeline.makeStartedImageTask(with: Test.request) { event, _ in
            if case .preview(let preview) = event {
                previews.append(preview)
                dataLoader.resume()
            }
        }
        let response = try await task.response

        // THEN only the final image is decompressed
        #expect(previews.count == 2)
        #expect(delegate.consultedResponses.map(\.isPreview) == [false])
        #expect(delegate.decompressedResponses.count == 1)
        #expect(response.container.userInfo[.isDecompressedKey] as? Bool == true)
    }

    /// ImageIO creates the thumbnails already decoded, so the default decoder
    /// doesn't offer them for decompression either.
    @Test func defaultDecoderDoesNotOfferThumbnailsForDecompression() async throws {
        // GIVEN the default decoder
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let request = ImageRequest(url: Test.url).with { $0.thumbnail = .init(maxPixelSize: 400) }

        // WHEN
        let response = try await pipeline.imageTask(with: request).response

        // THEN
        #expect(response.image.sizeInPixels == CGSize(width: 400, height: 300))
        #expect(delegate.consultedResponses.isEmpty)
        #expect(delegate.decompressedResponses.isEmpty)
    }
#endif
}

// MARK: - Helpers

private extension ImageContainer.UserInfoKey {
    static let isDecompressedKey: ImageContainer.UserInfoKey = "ImagePipelineDecompressionStageTests.isDecompressed"
}

private extension ImagePipeline {
    nonisolated func reconfiguredKeepingDelegate(_ delegate: any ImagePipeline.Delegate, _ configure: (inout ImagePipeline.Configuration) -> Void) -> ImagePipeline {
        var configuration = self.configuration
        configure(&configuration)
        return ImagePipeline(configuration: configuration, delegate: delegate)
    }
}

/// Records the decompression requests and performs them the way the default
/// implementation does, marking the result.
private final class DecompressionRecordingDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _consultedResponses: [ImageResponse] = []
    private var _decompressedResponses: [ImageResponse] = []
    private var _decompressedRequests: [ImageRequest] = []

    var consultedResponses: [ImageResponse] { lock.withLock { _consultedResponses } }
    var decompressedResponses: [ImageResponse] { lock.withLock { _decompressedResponses } }
    var decompressedRequests: [ImageRequest] { lock.withLock { _decompressedRequests } }

    func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
        lock.withLock { _consultedResponses.append(response) }
        return pipeline.configuration.isDecompressionEnabled
    }

    func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse {
        lock.withLock {
            _decompressedResponses.append(response)
            _decompressedRequests.append(request)
        }
        var response = response
        response.container.image = ImageDecompression.decompress(image: response.image)
        response.container.userInfo[.isDecompressedKey] = true
        return response
    }
}

/// Wraps the default decoder, and marks the images it produces as needing
/// decompression, including the previews if asked to.
private final class DecompressionFlaggingDecoder: ImageDecoding, @unchecked Sendable {
    private let decoder: ImageDecoders.Default
    private let isFlaggingPreviews: Bool

    init?(context: ImageDecodingContext, isFlaggingPreviews: Bool = false) {
        guard let decoder = ImageDecoders.Default(context: context) else {
            return nil
        }
        self.decoder = decoder
        self.isFlaggingPreviews = isFlaggingPreviews
    }

    var isAsynchronous: Bool { false }

    func decode(_ data: Data) throws -> ImageContainer {
        let container = try decoder.decode(data)
        ImageDecompression.setDecompressionNeeded(true, for: container.image)
        return container
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        let preview = decoder.decodePartiallyDownloadedData(data)
        if let preview, isFlaggingPreviews {
            ImageDecompression.setDecompressionNeeded(true, for: preview.image)
        }
        return preview
    }
}

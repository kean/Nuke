// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// Covers how `TaskFetchOriginalImage` decodes the data as it arrives – the
/// decoder it uses for a download, the throttling of the previews – and how
/// `TaskLoadImage` processes the previews.
///
/// The data loader serves a progressive JPEG in three chunks, the first two of
/// which are partial data.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineFetchOriginalImageTests {
    private let dataLoader: MockProgressiveDataLoader
    private let pipeline: ImagePipeline

    init() {
        let dataLoader = MockProgressiveDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }
    }

    // MARK: - Throttling

    @Test(arguments: zip([0, 3600] as [TimeInterval], [2, 1]))
    func previewsAreThrottledByTheProgressiveDecodingInterval(interval: TimeInterval, expectedPreviewCount: Int) async throws {
        // GIVEN a decoder that produces a preview for every chunk
        let decoder = ScriptedDecoder()
        let pipeline = pipeline.reconfigured {
            $0.progressiveDecodingInterval = interval
            $0.makeImageDecoder = { _ in decoder }
        }

        // WHEN
        let previews = LockedArray<ImageResponse>()
        let task = loadImage(with: pipeline, previews: previews)
        let response = try await task.response

        // THEN the chunks that arrive within the interval after a preview
        // aren't even decoded
        #expect(previews.count == expectedPreviewCount)
        #expect(decoder.partialDecodeCount == expectedPreviewCount)
        #expect(!response.isPreview)
    }

    /// The interval starts with a preview, not with an attempt to make one.
    @Test func chunkThatProducedNoPreviewDoesNotStartTheInterval() async throws {
        // GIVEN a decoder that can't make a preview from the first chunk, and
        // an interval longer than the test
        let decoder = ScriptedDecoder(failingPartialDecodes: [1])
        let pipeline = pipeline.reconfigured {
            $0.progressiveDecodingInterval = 3600
            $0.makeImageDecoder = { _ in decoder }
        }

        // WHEN
        let previews = LockedArray<ImageResponse>()
        let task = loadImage(with: pipeline, previews: previews)
        _ = try await task.response

        // THEN the second chunk is still decoded
        #expect(decoder.partialDecodeCount == 2)
        #expect(previews.count == 1)
    }

    // MARK: - Decoder

    /// A decoder is a one-shot object for a single decoding session: the one
    /// that produces the previews also decodes the final image, even though
    /// the context of the final image doesn't carry the preview policy the
    /// decoder was created with.
    @Test func oneDecoderDecodesThePreviewsAndTheFinalImage() async throws {
        // GIVEN a preview policy other than the default one, which the context
        // of the final image has
        let decoders = LockedArray<ScriptedDecoder>()
        let pipeline = ImagePipeline(delegate: PreviewPolicyDelegate(policies: [.thumbnail])) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.makeImageDecoder = { context in
                let decoder = ScriptedDecoder(context: context)
                decoders.append(decoder)
                return decoder
            }
        }

        // WHEN
        let previews = LockedArray<ImageResponse>()
        _ = try await loadImage(with: pipeline, previews: previews).response

        // THEN
        #expect(decoders.values.map(\.previewPolicy) == [.thumbnail])
        let decoder = try #require(decoders.values.first)
        #expect(decoder.partialDecodeCount == 2)
        #expect(decoder.finalDecodeCount == 1)
        #expect(previews.count == 2)
    }

    /// A decoder created while the previews were disabled produced no previews,
    /// so it is replaced when the policy for more data enables them.
    @Test func decoderIsReplacedWhenThePreviewPolicyEnablesPreviews() async throws {
        // GIVEN a policy that enables the previews from the second chunk
        let decoders = LockedArray<ScriptedDecoder>()
        let pipeline = ImagePipeline(delegate: PreviewPolicyDelegate(policies: [.disabled, .incremental])) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.makeImageDecoder = { context in
                let decoder = ScriptedDecoder(context: context)
                decoders.append(decoder)
                return decoder
            }
        }

        // WHEN
        let previews = LockedArray<ImageResponse>()
        _ = try await loadImage(with: pipeline, previews: previews).response

        // THEN the second decoder produces the preview and the final image
        #expect(decoders.values.map(\.previewPolicy) == [.disabled, .incremental])
        #expect(decoders.values.map(\.finalDecodeCount) == [0, 1])
        #expect(previews.count == 1)
    }

    @Test func decoderIsRequestedAgainWhenThereIsNoneForPartialData() async throws {
        // GIVEN a factory that only has a decoder for the complete data
        let isCompleted = LockedArray<Bool>()
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { context in
                isCompleted.append(context.isCompleted)
                guard context.isCompleted else { return nil }
                return ImageDecoders.Default(context: context)
            }
        }

        // WHEN
        let previews = LockedArray<ImageResponse>()
        let response = try await loadImage(with: pipeline, previews: previews).response

        // THEN the factory is asked for every chunk, and the missing decoder
        // for the partial data doesn't fail the request
        #expect(isCompleted.values == [false, false, true])
        #expect(previews.count == 0)
        #expect(response.image.sizeInPixels == CGSize(width: 450, height: 300))
    }

    // MARK: - Processing Previews

    @Test @ImagePipelineActor func previewsArrivingWhileProcessingIsBusyAreDropped() async throws {
        // GIVEN a decoder that makes a preview of every chunk as it arrives – a
        // decode on the decoding queue can be dropped or cancelled before its
        // preview reaches the processing – and a suspended processing queue
        let decoder = ScriptedDecoder()
        let pipeline = pipeline.reconfigured {
            $0.makeImageDecoder = { _ in decoder }
        }
        let processors = MockProcessorFactory()
        let queue = pipeline.configuration.imageProcessingQueue
        queue.isSuspended = true
        let expectation = TestExpectation(queue: queue, count: 2)

        // WHEN the whole image is downloaded while the first preview waits
        let request = ImageRequest(url: Test.url, processors: [processors.make(id: "1")])
        let previews = LockedArray<ImageResponse>()
        let task = loadImage(with: pipeline, request: request, previews: previews)
        await expectation.wait()
        queue.isSuspended = false
        let response = try await task.response

        // THEN both previews are decoded, but only the first one and the final
        // image are scheduled, and the final image cancels the preview
        #expect(decoder.partialDecodeCount == 2)
        #expect(expectation.operations.count == 2)
        #expect(expectation.operations.first?.isCancelled == true)
        #expect(processors.numberOfProcessorsApplied == 1)
        #expect(previews.count == 0)
        #expect(response.image.nk_test_processorIDs == ["1"])
    }

    @Test func previewsThatFailProcessingAreSkipped() async throws {
        // GIVEN a processor that fails for the previews
        let didRejectPreview = TestExpectation()
        let processor = ScriptedProcessor(isFailingPreviews: true) {
            didRejectPreview.fulfill()
        }
        let request = ImageRequest(url: Test.url, processors: [processor])
        let remainingChunkCount = dataLoader.chunks.count - 1

        // WHEN a preview fails processing
        let events = LockedArray<ImageTask.Event>()
        let task = pipeline.makeStartedImageTask(with: request) { event, _ in
            events.append(event)
        }
        await didRejectPreview.wait()
        for _ in 0..<remainingChunkCount {
            dataLoader.resume()
        }
        let response = try await task.response

        // THEN the task carries on, and no previews are delivered
        #expect(!response.isPreview)
        #expect(!events.values.contains { if case .preview = $0 { true } else { false } })
    }

    @Test func finalImageThatFailsProcessingFailsTheTaskAfterThePreviews() async throws {
        // GIVEN a processor that fails only for the final image
        let request = ImageRequest(url: Test.url, processors: [ScriptedProcessor(isFailingFinalImage: true)])

        // WHEN
        let previews = LockedArray<ImageResponse>()
        let dataLoader = dataLoader
        let task = pipeline.makeStartedImageTask(with: request) { event, _ in
            if case .preview(let preview) = event {
                previews.append(preview)
                dataLoader.resume()
            }
        }

        // THEN the processed previews are delivered, then the failure
        do {
            _ = try await task.response
            Issue.record("Expected the request to fail")
        } catch {
            guard case let .processingFailed(processor, context, _) = error else {
                Issue.record("Expected .processingFailed, got \(error)")
                return
            }
            #expect(processor.identifier == "scripted")
            #expect(context.isCompleted)
            #expect(!context.response.isPreview)
        }
        #expect(previews.count == 2)
        #expect(previews.values.allSatisfy { $0.isPreview && $0.image.nk_test_processorIDs == ["scripted"] })
    }

    // MARK: - Helpers

    /// Starts loading the image, serving the next chunk of data for every
    /// progress update, and recording the previews.
    private func loadImage(with pipeline: ImagePipeline, request: ImageRequest = Test.request, previews: LockedArray<ImageResponse>) -> ImageTask {
        let dataLoader = dataLoader
        return pipeline.makeStartedImageTask(with: request) { event, _ in
            switch event {
            case .progress:
                dataLoader.resume()
            case .preview(let preview):
                previews.append(preview)
            case .finished:
                break
            }
        }
    }
}

// MARK: - Helpers

private final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element] = []

    func append(_ element: Element) {
        lock.withLock { elements.append(element) }
    }

    var values: [Element] {
        lock.withLock { elements }
    }

    var count: Int {
        values.count
    }
}

/// A synchronous decoder that makes a preview of every chunk of data, unless
/// the previews are disabled or it's told to fail on the given chunks.
private final class ScriptedDecoder: ImageDecoding, @unchecked Sendable {
    let previewPolicy: ImagePipeline.PreviewPolicy
    private let failingPartialDecodes: Set<Int>
    private let image = Test.rgbImage(width: 4, height: 4)
    private let lock = NSLock()
    private var _partialDecodeCount = 0
    private var _finalDecodeCount = 0

    var partialDecodeCount: Int { lock.withLock { _partialDecodeCount } }
    var finalDecodeCount: Int { lock.withLock { _finalDecodeCount } }

    /// - parameter failingPartialDecodes: The one-based indices of the partial
    /// decodes that produce no preview.
    init(previewPolicy: ImagePipeline.PreviewPolicy = .incremental, failingPartialDecodes: Set<Int> = []) {
        self.previewPolicy = previewPolicy
        self.failingPartialDecodes = failingPartialDecodes
    }

    convenience init(context: ImageDecodingContext) {
        self.init(previewPolicy: context.previewPolicy)
    }

    var isAsynchronous: Bool { false }

    func decode(_ data: Data) throws -> ImageContainer {
        lock.withLock { _finalDecodeCount += 1 }
        return ImageContainer(image: image)
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        let index = lock.withLock {
            _partialDecodeCount += 1
            return _partialDecodeCount
        }
        guard previewPolicy != .disabled, !failingPartialDecodes.contains(index) else {
            return nil
        }
        return ImageContainer(image: image, isPreview: true)
    }
}

/// Returns the given policies in order, then keeps returning the last one.
private final class PreviewPolicyDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    private let policies: [ImagePipeline.PreviewPolicy]
    private let lock = NSLock()
    private var requestCount = 0

    init(policies: [ImagePipeline.PreviewPolicy]) {
        self.policies = policies
    }

    func previewPolicy(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImagePipeline.PreviewPolicy {
        let index = lock.withLock {
            defer { requestCount += 1 }
            return min(requestCount, policies.count - 1)
        }
        return policies[index]
    }
}

/// Marks the images it processes, failing either the previews or the final
/// image when asked to.
private struct ScriptedProcessor: ImageProcessing {
    var isFailingPreviews = false
    var isFailingFinalImage = false
    var onPreview: @Sendable () -> Void = {}

    var identifier: String { "scripted" }

    func process(_ image: PlatformImage) -> PlatformImage? {
        MockImageProcessor(id: identifier).process(image)
    }

    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        if !context.isCompleted {
            onPreview()
        }
        if context.isCompleted ? isFailingFinalImage : isFailingPreviews {
            throw MockError(description: "processor-failed")
        }
        guard let image = process(container.image) else {
            throw ImageProcessingError.unknown
        }
        var container = container
        container.image = image
        return container
    }
}

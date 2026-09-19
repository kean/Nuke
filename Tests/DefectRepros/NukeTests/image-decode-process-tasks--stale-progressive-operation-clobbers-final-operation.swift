// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG: a progressive decode/processing operation that finishes after the final
// one was scheduled clears the task's handle to the *final* operation, so the
// final decode/processing can no longer be cancelled (or re-prioritized).
//
// Expected: cancelling the `ImageTask` cancels the outstanding work –
// `AsyncTask.operation` is "the outstanding operation ... It's only cancelled
// when the task is cancelled" – and priority changes reach it
// (`AsyncTask.priority.didSet` → `operation?.priority`).
//
// Actual: when the final data (or final image) arrives while a preview is
// being decoded (or processed), the task cancels the preview operation – which
// keeps running, `TaskQueue.Operation.cancel()` can't stop a running one – and
// stores the final operation in `operation`. When the preview operation then
// finishes, it runs `self?.operation = nil` unconditionally
// (`AsyncPipelineTask.decode`, `TaskLoadImage.process`, and
// `TaskLoadImage.didReceiveImageResponse` for decompression), dropping the
// handle to the final operation. Cancelling the image task after that leaves
// the final decode/processing running to completion for nobody, and a
// priority change never reaches it. The fix is to clear the handle only if it
// still refers to the operation that is finishing.
//
// Sources/Nuke/Tasks/AsyncPipelineTask.swift:96 (decode), Sources/Nuke/Tasks/TaskLoadImage.swift:94 (process)
@Suite(.timeLimit(.minutes(5)))
struct StaleProgressiveOperationBugRepro {
    @Test @ImagePipelineActor func finalDecodeIsCancelledAfterALatePreviewDecode() async throws {
        // GIVEN a decoder that blocks on both the preview and the final image
        let dataLoader = MockProgressiveDataLoader()
        let decoder = GatedDecoder()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.makeImageDecoder = { _ in decoder }
        }
        let queue = pipeline.configuration.imageDecodingQueue
        let operations = TestExpectation(queue: queue, count: 2)
        let didDeliverPreview = TestExpectation()
        let task = pipeline.makeStartedImageTask(with: Test.request) { event, _ in
            if case .preview = event { didDeliverPreview.fulfill() }
        }
        defer { decoder.openAllGates() }

        // WHEN the rest of the data arrives while the first preview is decoded
        await decoder.didStartPreview.wait()
        dataLoader.resume()
        dataLoader.resume()
        await operations.wait()
        await decoder.didStartFinal.wait()

        // WHEN the preview decode finishes after the final one started
        decoder.openPreviewGate()
        await didDeliverPreview.wait()

        // WHEN the task is cancelled
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }

        // THEN the final decode is cancelled with it
        #expect(operations.operations.count == 2)
        #expect(operations.operations.first?.isCancelled == true)
        #expect(operations.operations.last?.isCancelled == true) // Actual: false
    }

    @Test @ImagePipelineActor func finalProcessingIsCancelledAfterALatePreviewProcessing() async throws {
        // GIVEN a processor that blocks on both the preview and the final image
        let dataLoader = MockProgressiveDataLoader()
        let processor = GatedProcessor()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }
        let queue = pipeline.configuration.imageProcessingQueue
        let operations = TestExpectation(queue: queue, count: 2)
        let didDeliverPreview = TestExpectation()
        let request = ImageRequest(url: Test.url, processors: [processor])
        let task = pipeline.makeStartedImageTask(with: request) { event, _ in
            if case .preview = event { didDeliverPreview.fulfill() }
        }
        defer { processor.openAllGates() }

        // WHEN the rest of the data arrives while the first preview is processed
        await processor.didStartPreview.wait()
        dataLoader.resume()
        dataLoader.resume()
        await operations.wait()
        await processor.didStartFinal.wait()

        // WHEN the preview processing finishes after the final one started
        processor.openPreviewGate()
        await didDeliverPreview.wait()

        // WHEN the task is cancelled
        task.cancel()
        await #expect(throws: ImagePipeline.Error.cancelled) {
            try await task.response
        }

        // THEN the final processing is cancelled with it
        #expect(operations.operations.count == 2)
        #expect(operations.operations.first?.isCancelled == true)
        #expect(operations.operations.last?.isCancelled == true) // Actual: false
    }
}

/// Two semaphore gates: one for the previews, one for the final image.
private final class Gates: @unchecked Sendable {
    let didStartPreview = TestExpectation()
    let didStartFinal = TestExpectation()
    private let previewGate = DispatchSemaphore(value: 0)
    private let finalGate = DispatchSemaphore(value: 0)

    func waitForPreviewGate() {
        didStartPreview.fulfill()
        _ = previewGate.wait(timeout: .now() + 30)
    }

    func waitForFinalGate() {
        didStartFinal.fulfill()
        _ = finalGate.wait(timeout: .now() + 30)
    }

    func openPreviewGate() {
        previewGate.signal()
    }

    func openAllGates() {
        for _ in 0..<4 {
            previewGate.signal()
            finalGate.signal()
        }
    }
}

/// Decodes on the decoding queue, blocking until the gates open.
private final class GatedDecoder: ImageDecoding, @unchecked Sendable {
    private let gates = Gates()
    private let decoder = ImageDecoders.Default()
    var didStartPreview: TestExpectation { gates.didStartPreview }
    var didStartFinal: TestExpectation { gates.didStartFinal }

    func decode(_ data: Data) throws -> ImageContainer {
        gates.waitForFinalGate()
        return try decoder.decode(data)
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        gates.waitForPreviewGate()
        return ImageContainer(image: Test.rgbImage(width: 4, height: 4), isPreview: true)
    }

    func openPreviewGate() { gates.openPreviewGate() }
    func openAllGates() { gates.openAllGates() }
}

/// Processes the images, blocking until the gates open.
private final class GatedProcessor: ImageProcessing, @unchecked Sendable {
    private let gates = Gates()
    var didStartPreview: TestExpectation { gates.didStartPreview }
    var didStartFinal: TestExpectation { gates.didStartFinal }

    var identifier: String { "gated" }

    func process(_ image: PlatformImage) -> PlatformImage? {
        image
    }

    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        if context.isCompleted {
            gates.waitForFinalGate()
        } else {
            gates.waitForPreviewGate()
        }
        return container
    }

    func openPreviewGate() { gates.openPreviewGate() }
    func openAllGates() { gates.openAllGates() }
}

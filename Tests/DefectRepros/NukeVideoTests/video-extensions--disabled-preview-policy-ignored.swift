// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// SUSPECTED BUG: `ImageDecoders.Video` ignores `ImageDecodingContext.previewPolicy`
// and produces a preview from partially downloaded data even when the policy
// is `.disabled`.
//
// Source: Sources/NukeVideo/ImageDecoders+Video.swift:29 (`init?(context:)`
// never reads `context.previewPolicy`) and :45 (`decodePartiallyDownloadedData`
// always tries to make a preview).
//
// Contract:
// - `ImagePipeline.PreviewPolicy.disabled`: "No previews are generated for
//   partially downloaded data." / ImagePipeline docs: "`.disabled` — No previews."
// - `PreviewPolicy.default(for:)` returns `.disabled` for MP4, and the format
//   matrix in supported-image-formats.md lists "–" under Previews for
//   MP4/M4V/MOV.
// - Precedent: CHANGELOG "Fix `ImageDecoders/Default` generating GIF previews
//   even when the preview policy is `.disabled`" (#892).
//
// Expected: with a delegate that returns `.disabled` (or with the default
// delegate, which resolves MP4 to `.disabled`), a progressive download of a
// video delivers no previews, and the decoder doesn't run AVFoundation on the
// partial data.
// Actual: the video decoder makes an `AVAssetImageGenerator` preview of the
// partial data and the pipeline delivers it as a `.preview` event. For a video
// whose movie header is at the end, it runs the generator – and fails – on
// every chunk until the download completes.
//
// Drop into Tests/NukeVideoTests and run:
//   swift test --filter VideoDecoderDisabledPreviewPolicyBugTests

import Testing
import AVFoundation
import NukeVideo

#if !os(watchOS) && !os(visionOS)

@Suite(.timeLimit(.minutes(5)))
struct VideoDecoderDisabledPreviewPolicyBugTests {
    @Test func decoderCreatedWithDisabledPolicyProducesNoPreview() async throws {
        // Given
        let data = try await makeFastStartVideo()
        let partial = data.prefix(data.count * 9 / 10)
        let context = ImageDecodingContext(request: ImageRequest(url: nil), data: partial, isCompleted: false, previewPolicy: .disabled)
        let decoder = try #require(ImageDecoders.Video(context: context))

        // When
        let preview = decoder.decodePartiallyDownloadedData(partial)

        // Then
        #expect(preview == nil, "The decoder was told not to produce previews")
    }

    @Test(arguments: [true, false])
    func pipelineDeliversNoVideoPreviewWhenPolicyIsDisabled(usesDefaultDelegate: Bool) async throws {
        // Given the first 90% of a video laid out for progressive download.
        // The rest is sent once the decoder has seen the partial data.
        let data = try await makeFastStartVideo()
        #expect(ImagePipeline.PreviewPolicy.default(for: data) == .disabled)
        let dataLoader = GatedDataLoader(data: data, firstChunkCount: data.count * 9 / 10)
        let registry = ImageDecoderRegistry()
        registry.register(ImageDecoders.Video.init)
        let delegate: DisabledPreviewPolicyDelegate? = usesDefaultDelegate ? nil : DisabledPreviewPolicyDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.makeImageDecoder = { context in
                guard let decoder = registry.decoder(for: context) else {
                    // A decoder that declines partial data is a fix too.
                    if !context.isCompleted { dataLoader.sendRemainingData() }
                    return nil
                }
                return NotifyingDecoder(decoder: decoder, didDecodePartialData: dataLoader.sendRemainingData)
            }
        }

        // When
        let task = pipeline.imageTask(with: URL(string: "https://example.com/video.mp4")!)
        var previews: [ImageResponse] = []
        for await event in task.events {
            if case .preview(let response) = event {
                previews.append(response)
            }
        }
        _ = try await task.response

        // Then
        #expect(previews.isEmpty, "Got \(previews.count) preview(s) with a .disabled preview policy")
    }
}

private final class DisabledPreviewPolicyDelegate: ImagePipeline.Delegate {
    func previewPolicy(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImagePipeline.PreviewPolicy {
        .disabled
    }
}

/// Forwards to the decoder and reports when a partial decode is over.
private struct NotifyingDecoder: ImageDecoding {
    let decoder: any ImageDecoding
    let didDecodePartialData: @Sendable () -> Void

    var isAsynchronous: Bool { decoder.isAsynchronous }

    func decode(_ data: Data) throws -> ImageContainer {
        try decoder.decode(data)
    }

    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
        defer { didDecodePartialData() }
        return decoder.decodePartiallyDownloadedData(data)
    }
}

/// Sends the first chunk of the data right away, and the rest when asked to.
private final class GatedDataLoader: DataLoading {
    private let data: Data
    private let firstChunkCount: Int
    private let gate = AsyncStream<Void>.makeStream()

    init(data: Data, firstChunkCount: Int) {
        self.data = data
        self.firstChunkCount = firstChunkCount
    }

    @Sendable func sendRemainingData() {
        gate.continuation.finish()
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let response = URLResponse(url: request.url!, mimeType: "video/mp4", expectedContentLength: data.count, textEncodingName: nil)
        let (data, firstChunkCount, gate) = (data, firstChunkCount, gate.stream)
        let task = Task {
            didReceiveData(data.prefix(firstChunkCount), response)
            for await _ in gate {}
            didReceiveData(data.suffix(from: firstChunkCount), response)
            completion(nil)
        }
        return TaskCancellable(task: task)
    }
}

private struct TaskCancellable: Cancellable {
    let task: Task<Void, Never>

    func cancel() {
        task.cancel()
    }
}

/// Encodes a 90-frame H.264 video with the movie header in front of the samples.
private func makeFastStartVideo() async throws -> Data {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: url) }
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 32,
        AVVideoHeightKey: 16
    ])
    writer.add(input)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 32,
        kCVPixelBufferHeightKey as String: 16
    ])
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let pool = try #require(adaptor.pixelBufferPool)
    for frame in 0..<90 {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(1))
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        adaptor.append(try #require(buffer), withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: 90, timescale: 30))
    await writer.finishWriting()
    return try Data(contentsOf: url)
}

#endif

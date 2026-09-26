// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import AVFoundation
import NukeVideo

#if !os(watchOS) && !os(visionOS)

/// Loads videos through an `ImagePipeline` the way the documentation sets it
/// up, with the video decoder registered. Each test uses a registry of its own
/// rather than `ImageDecoderRegistry.shared`, which the suites share.
@Suite(.timeLimit(.minutes(5)))
struct VideoPipelineTests {
    @Test func loadsVideoWithRegisteredDecoder() async throws {
        // Given
        let data = try await VideoFixture(width: 32, height: 16).makeData()
        let pipeline = makePipeline(decoders: .video)

        // When
        let response = try await pipeline.imageTask(with: ImageRequest(id: "video", data: { data })).response

        // Then
        #expect(response.container.type == .mp4)
        #expect(!response.container.isPreview)
        #expect(response.image.cgImage?.width == 32)
        #expect(response.image.cgImage?.height == 16)
        let asset = try #require(response.container.userInfo[.videoAssetKey] as? AVAsset)
        #expect(try await asset.load(.isPlayable))
    }

    /// "Video types are recognized without `NukeVideo`, but only
    /// `ImageDecoders.Video` can decode them, and you have to register it yourself."
    @Test func failsToDecodeVideoWithoutVideoDecoder() async throws {
        // Given a registry with only the default decoder
        let data = try await VideoFixture().makeData()
        let pipeline = makePipeline(decoders: .default)

        // When
        let error = await #expect(throws: ImagePipeline.Error.self) {
            try await pipeline.imageTask(with: ImageRequest(id: "video", data: { data })).response
        }

        // Then
        guard case .decodingFailed(let decoder, let context, _)? = error else {
            Issue.record("Expected decoding to fail, got \(String(describing: error))")
            return
        }
        #expect(decoder is ImageDecoders.Default)
        #expect(AssetType(context.data) == .mp4)
    }

    /// Processors transform the still preview, and the asset attached to it
    /// keeps playing the original video.
    @Test func processorsKeepVideoAsset() async throws {
        // Given
        let data = try await VideoFixture(width: 32, height: 16).makeData()
        let pipeline = makePipeline(decoders: .video)
        let request = ImageRequest(id: "video", data: { data }, processors: [.resize(width: 8, unit: .pixels)])

        // When
        let response = try await pipeline.imageTask(with: request).response

        // Then
        #expect(response.image.cgImage?.width == 8)
        #expect(response.image.cgImage?.height == 4)
        #expect(response.container.type == .mp4)
        let asset = try #require(response.container.userInfo[.videoAssetKey] as? AVAsset)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 32, height: 16))
    }

    /// A video decoded by the pipeline is stored in the memory cache with its
    /// asset, so that showing it again doesn't decode it again.
    @Test func memoryCacheKeepsVideoAsset() async throws {
        // Given
        let data = try await VideoFixture().makeData()
        let pipeline = makePipeline(decoders: .video)
        let request = ImageRequest(id: "video", data: { data })
        let first = try await pipeline.imageTask(with: request).response

        // When
        let second = try await pipeline.imageTask(with: request).response

        // Then
        #expect(first.cacheType == nil)
        #expect(second.cacheType == .memory)
        let firstAsset = try #require(first.container.userInfo[.videoAssetKey] as? AVAsset)
        let secondAsset = try #require(second.container.userInfo[.videoAssetKey] as? AVAsset)
        #expect(firstAsset === secondAsset)
    }

    /// With progressive decoding on and a policy that asks for previews, the
    /// first frame of a video laid out for progressive download is shown
    /// before the download completes.
    @Test func deliversPreviewBeforeDownloadCompletes() async throws {
        // Given the first 90% of the video, with the rest held back until the
        // decoder is done with the partial data
        let data = try await VideoFixture(frameCount: 90, isFastStart: true).makeData()
        let dataLoader = GatedDataLoader(data: data, firstChunkCount: data.count * 9 / 10)
        let pipeline = makePipeline(decoders: .video, previewPolicy: .incremental, didDecodePartialData: dataLoader.sendRemainingData) {
            $0.dataLoader = dataLoader
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }

        // When
        let task = pipeline.imageTask(with: URL(string: "https://example.com/video.mp4")!)
        var previews: [ImageResponse] = []
        for await event in task.events {
            if case .preview(let response) = event {
                previews.append(response)
            }
        }
        let response = try await task.response

        // Then
        #expect(previews.count == 1)
        let preview = try #require(previews.first)
        #expect(preview.container.isPreview)
        #expect(preview.container.type == .mp4)
        #expect(preview.container.userInfo[.videoAssetKey] is AVAsset)
        #expect(preview.image.cgImage?.width == 32)
        #expect(!response.container.isPreview)
        #expect(response.container.data == data)
    }
}

// MARK: - Helpers

private enum Decoders {
    case `default`, video
}

/// - parameter didDecodePartialData: Called when a decoder is done with
///   partially downloaded data, or when no decoder is available for it.
private func makePipeline(
    decoders: Decoders,
    previewPolicy: ImagePipeline.PreviewPolicy? = nil,
    didDecodePartialData: (@Sendable () -> Void)? = nil,
    _ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }
) -> ImagePipeline {
    let registry = ImageDecoderRegistry()
    if decoders == .video {
        registry.register(ImageDecoders.Video.init)
    }
    let delegate = previewPolicy.map(MockPreviewPolicyDelegate.init(policy:))
    return ImagePipeline(delegate: delegate) {
        $0.makeImageDecoder = { context in
            guard let didDecodePartialData else {
                return registry.decoder(for: context)
            }
            guard let decoder = registry.decoder(for: context) else {
                if !context.isCompleted { didDecodePartialData() }
                return nil
            }
            return NotifyingDecoder(decoder: decoder, didDecodePartialData: didDecodePartialData)
        }
        $0.imageCache = ImageCache()
        configure(&$0)
    }
}

/// Forwards to a decoder and reports when it is done with partial data.
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

#endif

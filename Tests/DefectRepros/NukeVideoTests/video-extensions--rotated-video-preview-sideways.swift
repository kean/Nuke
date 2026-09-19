// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// SUSPECTED BUG: `ImageDecoders.Video` ignores the track's preferred transform,
// so the preview of a rotated video (every portrait video recorded on a phone)
// comes out sideways.
//
// Source: Sources/NukeVideo/ImageDecoders+Video.swift:75 – `makePreview(for:type:)`
// creates an `AVAssetImageGenerator` without setting
// `appliesPreferredTrackTransform = true` (it is `false` by default), so the
// frame is returned in its encoded orientation.
//
// Expected: a video encoded 32×16 with a 90° preferred transform plays 16 wide
// and 32 tall – that is how `AVPlayerLayer`/`VideoPlayerView` shows it – so the
// preview that stands in for it (`decode(_:)` and
// `decodePartiallyDownloadedData(_:)`) is 16×32.
// Actual: the preview is 32×16, rotated by 90° relative to the video that
// replaces it once playback starts.
//
// Drop into Tests/NukeVideoTests and run:
//   swift test --filter VideoDecoderRotatedPreviewBugTests

import Testing
import AVFoundation
import NukeVideo

#if !os(watchOS) && !os(visionOS)

@Suite(.timeLimit(.minutes(5)))
struct VideoDecoderRotatedPreviewBugTests {
    /// A portrait video the way a phone records it: the pixels are encoded
    /// landscape and the track's preferred transform rotates them by 90°.
    private let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 16, ty: 0)

    @Test func previewOfRotatedVideoIsInDisplayOrientation() async throws {
        // Given
        let data = try await makeVideo(width: 32, height: 16, transform: transform)
        let decoder = try #require(ImageDecoders.Video(context: ImageDecodingContext(request: ImageRequest(url: nil), data: data)))

        // When
        let container = try decoder.decode(data)

        // Then AVFoundation displays the video 16 wide and 32 tall...
        let asset = try #require(container.userInfo[.videoAssetKey] as? AVAsset)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let displaySize = naturalSize.applying(preferredTransform)
        #expect(abs(displaySize.width) == 16 && abs(displaySize.height) == 32)

        // ...so the preview has to be 16 wide and 32 tall too
        let image = try #require(cgImage(container.image))
        #expect(image.width == 16, "The preview is \(image.width)×\(image.height)")
        #expect(image.height == 32, "The preview is \(image.width)×\(image.height)")
    }

    @Test func partialPreviewOfRotatedVideoIsInDisplayOrientation() async throws {
        // Given
        let data = try await makeVideo(width: 32, height: 16, transform: transform)
        let decoder = try #require(ImageDecoders.Video(context: ImageDecodingContext(request: ImageRequest(url: nil), data: data, isCompleted: false)))

        // When
        let preview = try #require(decoder.decodePartiallyDownloadedData(data))

        // Then
        let image = try #require(cgImage(preview.image))
        #expect(image.width == 16, "The preview is \(image.width)×\(image.height)")
        #expect(image.height == 32, "The preview is \(image.width)×\(image.height)")
    }
}

private func cgImage(_ image: PlatformImage) -> CGImage? {
#if os(macOS)
    image.cgImage(forProposedRect: nil, context: nil, hints: nil)
#else
    image.cgImage
#endif
}

/// Encodes a short H.264 video with the given track transform.
private func makeVideo(width: Int, height: Int, transform: CGAffineTransform) async throws -> Data {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: url) }
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ])
    input.transform = transform
    writer.add(input)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ])
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let pool = try #require(adaptor.pixelBufferPool)
    for frame in 0..<6 {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(1))
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        adaptor.append(try #require(buffer), withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: 6, timescale: 30))
    await writer.finishWriting()
    return try Data(contentsOf: url)
}

#endif

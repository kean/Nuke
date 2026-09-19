// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// SUSPECTED BUG: decoding a video from a `Data` slice (a `Data` whose
// `startIndex` isn't 0) crashes the process.
//
// Source: Sources/NukeVideo/AVDataAsset.swift:75 and :78 – the resource loader
// subscripts `data` with AVFoundation's requested offsets as if they were
// indices: `data[dataRequest.requestedOffset...]` and
// `data[requestedOffset..<(requestedOffset + requestedLength)]`. Offsets are
// relative to the start of the resource, but `Data` indices of a slice start
// at `startIndex`, so the first request (offset 0) is out of bounds and `Data`
// traps (EXC_BREAKPOINT in `Data.subscript.getter`, called from
// `DataAssetResourceLoader.resourceLoader(_:shouldWaitForLoadingOfRequestedResource:)`
// on a global queue).
//
// Reachable through public API without calling the decoder directly:
// `ImageRequest(id:data:)` hands the data it returns to the decoder as is, and
// so does the pipeline for the first chunk a custom `DataLoading` sends
// (`TaskFetchOriginalData`: `if data.isEmpty { data = chunk }`). Slices are
// what `Data.dropFirst`, `suffix(from:)`, `subdata`-free parsing of a
// multipart/archive payload, etc. return. `AssetType(_:)` and
// `ImageDecoders.Default` handle slices; only the video path crashes.
//
// Expected: the video decodes, with the same first frame as the same bytes in
// a fresh `Data`.
// Actual: the process crashes with SIGTRAP.
//
// The tests run the crashing code in a child process (exit tests), so the
// failure is reported without taking the test runner down. macOS only.
//
// Drop into Tests/NukeVideoTests and run:
//   swift test --filter VideoDataSliceCrashBugTests

import Testing
import AVFoundation
import NukeVideo

#if os(macOS)

@Suite(.timeLimit(.minutes(5)))
struct VideoDataSliceCrashBugTests {
    @Test func decoderDecodesVideoPassedAsDataSlice() async {
        await #expect(processExitsWith: .success) {
            // Given the bytes of a video that start 100 bytes into a buffer
            let video = try await makeVideo()
            let buffer = Data(repeating: 0, count: 100) + video
            let slice = buffer[100...]
            #expect(slice == video)
            let decoder = try #require(ImageDecoders.Video(context: ImageDecodingContext(request: ImageRequest(url: nil), data: slice)))

            // When
            let container = try decoder.decode(slice)

            // Then
            #expect(container.image.size == CGSize(width: 32, height: 16))
        }
    }

    @Test func pipelineLoadsVideoReturnedAsDataSlice() async {
        await #expect(processExitsWith: .success) {
            // Given a request whose data closure returns a slice
            let video = try await makeVideo()
            let buffer = Data(repeating: 0, count: 100) + video
            let registry = ImageDecoderRegistry()
            registry.register(ImageDecoders.Video.init)
            let pipeline = ImagePipeline {
                $0.makeImageDecoder = { registry.decoder(for: $0) }
                $0.imageCache = nil
            }
            let request = ImageRequest(id: "video", data: { buffer[100...] })

            // When
            let response = try await pipeline.imageTask(with: request).response

            // Then
            #expect(response.image.size == CGSize(width: 32, height: 16))
            #expect(response.container.userInfo[.videoAssetKey] is AVAsset)
        }
    }
}

/// Encodes a short 32×16 H.264 video.
private func makeVideo() async throws -> Data {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: url) }
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
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

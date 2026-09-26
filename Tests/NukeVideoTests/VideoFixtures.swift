// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import AVFoundation
import CoreVideo
import NukeVideo

#if !os(watchOS)

/// Describes a small H.264 video that the tests encode on the fly. They are
/// generated rather than checked in because the test target ships no
/// resources, and because generating them lets each test pick the container,
/// the dimensions, the layout, and the colors of the frames it asserts on.
struct VideoFixture: Sendable {
    /// The width of the video track in pixels.
    var width = 32
    /// The height of the video track in pixels.
    var height = 16
    var frameCount = 6
    var frameRate: Int32 = 30
    var fileType: AVFileType = .mp4
    /// Moves the movie header in front of the samples, the way a video meant
    /// for progressive download is laid out.
    var isFastStart = false
    /// The color of each frame as (red, green, blue). The first frame is red
    /// and the rest are blue, so a test can tell which one a thumbnail shows.
    var color: @Sendable (_ frame: Int) -> (UInt8, UInt8, UInt8) = { $0 == 0 ? (255, 0, 0) : (0, 0, 255) }

    var duration: CMTime {
        CMTime(value: CMTimeValue(frameCount), timescale: frameRate)
    }

    /// Encodes the video and returns the file contents.
    func makeData() async throws -> Data {
        let url = try await makeFile()
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    /// Encodes the video into a temporary file and returns its URL. The caller
    /// owns the file.
    func makeFile() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nuke-video-fixture-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        writer.shouldOptimizeForNetworkUse = isFastStart
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        #expect(writer.startWriting(), "\(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)

        let pool = try #require(adaptor.pixelBufferPool)
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixelBuffer = try #require(buffer)
            fill(pixelBuffer, with: color(frame))
            let time = CMTime(value: CMTimeValue(frame), timescale: frameRate)
            #expect(adaptor.append(pixelBuffer, withPresentationTime: time))
        }
        input.markAsFinished()
        // Without an explicit end, the last frame would have no duration.
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        try #require(writer.status == .completed, "\(String(describing: writer.error))")
        return url
    }

    private var pathExtension: String {
        switch fileType {
        case .mov: "mov"
        case .m4v: "m4v"
        default: "mp4"
        }
    }

    private func fill(_ buffer: CVPixelBuffer, with color: (UInt8, UInt8, UInt8)) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            let pixels = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<CVPixelBufferGetWidth(buffer) {
                pixels[column * 4 + 0] = color.2 // B
                pixels[column * 4 + 1] = color.1 // G
                pixels[column * 4 + 2] = color.0 // R
                pixels[column * 4 + 3] = 255
            }
        }
    }
}

#endif

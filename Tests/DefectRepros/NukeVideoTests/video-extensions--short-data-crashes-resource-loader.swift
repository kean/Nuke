// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// SUSPECTED BUG: `ImageDecoders.Video.decode(_:)` crashes the process when
// given fewer than two bytes, instead of returning or throwing.
//
// Source: Sources/NukeVideo/AVDataAsset.swift:77-78 – the resource loader
// answers a byte-range request with `data[requestedOffset..<(requestedOffset + requestedLength)]`
// without clamping the range to the data it has. AVFoundation's first loading
// request asks for the content information together with the first 2 bytes,
// regardless of the content length the delegate reports in the same call, so
// for 0 or 1 bytes of data the range is out of bounds and `Data` traps
// (EXC_BREAKPOINT in `Data.subscript.getter`, on a global queue).
//
// `decode(_:)` is public and takes the data to decode as an argument (the
// decoder is created from a context, but nothing ties the two together), so a
// caller that decodes data of its own – or an empty download – takes the whole
// app down. With 2..16 bytes of the same file it returns an empty image, which
// shows what the caller expects for data that has no frames.
//
// Expected: `decode(Data())` and `decode(Data([0]))` return a container with
// an empty image (as `decode` does for any data without a decodable frame), or
// throw.
// Actual: the process crashes with SIGTRAP.
//
// The tests run the crashing code in a child process (exit tests), so the
// failure is reported without taking the test runner down. macOS only.
//
// Drop into Tests/NukeVideoTests and run:
//   swift test --filter VideoShortDataCrashBugTests

import Testing
import AVFoundation
import NukeVideo

#if os(macOS)

@Suite(.timeLimit(.minutes(5)))
struct VideoShortDataCrashBugTests {
    @Test func decodingEmptyDataDoesNotCrash() async {
        await #expect(processExitsWith: .success) {
            let header = Data([0x00, 0x00, 0x00, 0x10]) + Data("ftypisom".utf8) + Data(count: 4)
            let decoder = try #require(ImageDecoders.Video(context: ImageDecodingContext(request: ImageRequest(url: nil), data: header)))
            let container = try? decoder.decode(Data())
            #expect(container == nil || container?.image.size == .zero)
        }
    }

    @Test func decodingOneByteDoesNotCrash() async {
        await #expect(processExitsWith: .success) {
            let header = Data([0x00, 0x00, 0x00, 0x10]) + Data("ftypisom".utf8) + Data(count: 4)
            let decoder = try #require(ImageDecoders.Video(context: ImageDecodingContext(request: ImageRequest(url: nil), data: header)))
            let container = try? decoder.decode(Data([0x00]))
            #expect(container == nil || container?.image.size == .zero)
        }
    }

    /// For contrast: two bytes and more are answered without a crash.
    @Test func decodingTwoBytesDoesNotCrash() async {
        await #expect(processExitsWith: .success) {
            let header = Data([0x00, 0x00, 0x00, 0x10]) + Data("ftypisom".utf8) + Data(count: 4)
            let decoder = try #require(ImageDecoders.Video(context: ImageDecodingContext(request: ImageRequest(url: nil), data: header)))
            let container = try? decoder.decode(header.prefix(2))
            #expect(container == nil || container?.image.size == .zero)
        }
    }
}

#endif

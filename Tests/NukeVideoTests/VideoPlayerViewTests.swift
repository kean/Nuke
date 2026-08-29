// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import AVFoundation
import NukeVideo

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Suite(.timeLimit(.minutes(5))) @MainActor
struct VideoPlayerViewTests {
    let host = WindowHost()

    /// A looping video that was paused while its view was out of the window
    /// resumes when the view is added back to it, on every platform.
    @Test func resumesLoopingVideoWhenAddedBackToWindow() async throws {
        let view = VideoPlayerView()
        view.asset = AVURLAsset(url: try await makeVideoFixture())
        host.add(view)
        view.play()

        let player = try #require(view.playerLayer.player)
        try await poll { player.rate != 0 }

        // The view leaves the window and playback is interrupted, the way it is
        // when the app goes to the background.
        view.removeFromSuperview()
        player.pause()
        #expect(player.rate == 0)

        host.add(view)

        #expect(player.rate != 0)
    }

    /// There is no player to resume until the video is played.
    @Test func addingViewWithoutPlayerToWindowDoesNothing() {
        let view = VideoPlayerView()
        host.add(view)

        #expect(view.playerLayer.player == nil)
    }
}

/// Keeps a window alive for the test and attaches views to it the way an app does.
@MainActor
final class WindowHost {
    private let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

#if os(macOS)
    private let window: NSWindow
#else
    private let window: UIWindow
#endif

    init() {
#if os(macOS)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSView(frame: frame)
        window.orderFront(nil)
#else
        window = UIWindow(frame: frame)
        window.isHidden = false
#endif
    }

    func add(_ view: VideoPlayerView) {
        view.frame = frame
#if os(macOS)
        window.contentView?.addSubview(view)
#else
        window.addSubview(view)
#endif
    }
}

/// Waits for a condition that AVFoundation only reaches asynchronously.
@MainActor
private func poll(
    _ condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    for _ in 0..<500 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for the player", sourceLocation: sourceLocation)
}

/// Writes a short video to a temporary file. It is generated rather than checked
/// in because the package target ships no test resources.
private func makeVideoFixture() async throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).mp4")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 16,
        AVVideoHeightKey: 16
    ])
    writer.add(input)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    // Long enough that playback can't reach the end while the test runs.
    let frameRate: Int32 = 30
    let pool = try #require(adaptor.pixelBufferPool)
    for frame in 0..<(frameRate * 10) {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(1))
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        adaptor.append(try #require(buffer), withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: frameRate))
    }
    input.markAsFinished()
    await writer.finishWriting()

    return url
}

#endif

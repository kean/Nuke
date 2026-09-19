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
        // Long enough that playback can't reach the end while the test runs.
        let url = try await VideoFixture(width: 16, height: 16, frameCount: 300).makeFile()
        view.asset = AVURLAsset(url: url)
        host.add(view)
        view.play()

        let player = try #require(view.playerLayer.player)
        try await waitUntil { player.rate != 0 }

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

#endif

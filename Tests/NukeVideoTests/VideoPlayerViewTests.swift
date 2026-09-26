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
    let host = TestWindow()

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
        await waitUntil { player.rate != 0 }

        // The view leaves the window and playback is interrupted, the way it is
        // when the app goes to the background.
        view.removeFromSuperview()
        player.pause()
        #expect(player.rate == 0)

        host.add(view)

        #expect(player.rate != 0)
    }
}

#endif

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import AVFoundation
import NukeVideo

#if !os(watchOS) && !os(visionOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Configuration

/// The player the view creates and how it's configured. None of these tests
/// wait for playback.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct VideoPlayerViewConfigurationTests {
    @Test func defaults() {
        let view = VideoPlayerView()

        #expect(view.videoGravity == .resizeAspectFill)
        #expect(view.animatesFrameChanges)
        #expect(view.isLooping)
        #expect(view.onVideoFinished == nil)
        #expect(view.asset == nil)
    }

    @Test func playerLayerIsCreatedOnceOnFirstAccess() {
        // Given
        let view = VideoPlayerView(frame: CGRect(x: 0, y: 0, width: 40, height: 30))
        #expect(sublayers(of: view).isEmpty)

        // When
        let playerLayer = view.playerLayer

        // Then it fills the view and is added to its layer once
        #expect(view.playerLayer === playerLayer)
        #expect(sublayers(of: view).filter { $0 === playerLayer }.count == 1)
        #expect(playerLayer.frame == view.bounds)
        #expect(playerLayer.videoGravity == .resizeAspectFill)
        #expect(playerLayer.player == nil)
#if os(macOS)
        #expect(view.wantsLayer)
#endif
    }

    @Test func videoGravityIsAppliedToPlayerLayer() {
        // Given a gravity set before the layer exists
        let view = VideoPlayerView()
        view.videoGravity = .resizeAspect

        // Then the layer is created with it
        #expect(view.playerLayer.videoGravity == .resizeAspect)

        // When the gravity changes after the layer exists
        view.videoGravity = .resize

        // Then the layer follows
        #expect(view.playerLayer.videoGravity == .resize)
    }

    @Test func layoutResizesPlayerLayer() {
        // Given
        let view = VideoPlayerView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let playerLayer = view.playerLayer

        // When
        view.frame = CGRect(x: 5, y: 5, width: 50, height: 60)
        layoutNow(view)

        // Then
        #expect(playerLayer.frame == CGRect(x: 0, y: 0, width: 50, height: 60))
    }

    /// With `animatesFrameChanges`, the new frame of the player layer is set
    /// with implicit actions enabled, so it animates along with the view.
    @Test func layoutAnimatesPlayerLayerFrameByDefault() {
        // Given
        let view = VideoPlayerView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let actions = LayerActionRecorder()
        view.playerLayer.delegate = actions

        // When
        view.frame = CGRect(x: 0, y: 0, width: 50, height: 60)
        layoutNow(view)

        // Then
        #expect(actions.enabledKeys.contains("bounds"))
        withExtendedLifetime(actions) {}
    }

    @Test func layoutDoesNotAnimatePlayerLayerFrameWhenDisabled() {
        // Given
        let view = VideoPlayerView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        view.animatesFrameChanges = false
        let actions = LayerActionRecorder()
        view.playerLayer.delegate = actions

        // When
        view.frame = CGRect(x: 0, y: 0, width: 50, height: 60)
        layoutNow(view)

        // Then the frame changes without looking up an action for it
        #expect(view.playerLayer.frame.size == CGSize(width: 50, height: 60))
        #expect(actions.enabledKeys.isEmpty)
        withExtendedLifetime(actions) {}
    }

    @Test func playWithoutAssetDoesNothing() {
        // Given
        let view = VideoPlayerView()

        // When
        view.play()
        view.restart()

        // Then not even the player layer is created
        #expect(sublayers(of: view).isEmpty)
        #expect(view.playerLayer.player == nil)
    }

    @Test func settingAssetDoesNotCreatePlayer() async throws {
        // Given
        let view = VideoPlayerView()

        // When
        view.asset = try await makeLongAsset()

        // Then
        #expect(view.playerLayer.player == nil)
    }

    @Test func playCreatesMutedPlayerForAsset() async throws {
        // Given
        let view = VideoPlayerView()
        let asset = try await makeLongAsset()
        view.asset = asset

        // When
        view.play()

        // Then
        let player = try #require(view.playerLayer.player)
        #expect(player is AVQueuePlayer)
        #expect(player.isMuted)
        #expect(!player.preventsDisplaySleepDuringVideoPlayback)
        #expect(player.actionAtItemEnd == .none)
        #expect(player.currentItem?.asset === asset)
    }

    @Test func playWithLoopingDisabledPausesAtEnd() async throws {
        // Given
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeLongAsset()

        // When
        view.play()

        // Then
        #expect(view.playerLayer.player?.actionAtItemEnd == .pause)
    }

    @Test func isLoopingUpdatesExistingPlayer() async throws {
        // Given
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        view.play()
        let player = try #require(view.playerLayer.player)

        // When/Then
        view.isLooping = false
        #expect(player.actionAtItemEnd == .pause)

        view.isLooping = true
        #expect(player.actionAtItemEnd == .none)
    }

    @Test func playAgainReplacesPlayer() async throws {
        // Given
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        view.play()
        let first = try #require(view.playerLayer.player)

        // When
        let asset = try await makeLongAsset()
        view.asset = asset
        view.play()

        // Then
        let second = try #require(view.playerLayer.player)
        #expect(second !== first)
        #expect(second.currentItem?.asset === asset)
    }

    @Test func settingAssetToNilRemovesPlayer() async throws {
        // Given
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        view.play()
        #expect(view.playerLayer.player != nil)

        // When
        view.asset = nil

        // Then
        #expect(view.playerLayer.player == nil)
    }

    @Test func resetRemovesPlayerAndKeepsAsset() async throws {
        // Given
        let view = VideoPlayerView()
        let asset = try await makeLongAsset()
        view.asset = asset
        view.play()

        // When
        view.reset()
        view.reset()

        // Then the view can play the same asset again
        #expect(view.playerLayer.player == nil)
        #expect(view.asset === asset)
        view.play()
        #expect(view.playerLayer.player?.currentItem?.asset === asset)
    }
}

// MARK: - Finish Notifications

/// The view reports the end of a video only for the item it is playing. The
/// end is posted by hand, which only reaches the observers of that item, and
/// the videos are long enough that playback can't reach the real end first.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct VideoPlayerViewFinishNotificationTests {
    @Test func reportsEndOfNonLoopingVideo() async throws {
        // Given
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeLongAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()

        // When
        postDidPlayToEnd(try #require(view.playerLayer.player?.currentItem))

        // Then
        #expect(finishedCount == 1)
    }

    @Test func doesNotReportEndOfLoopingVideo() async throws {
        // Given
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()
        let player = try #require(view.playerLayer.player)
        // The view seeks the item back to the start, which it can only do once
        // the item is ready.
        try await waitUntil { player.status == .readyToPlay }

        // When
        postDidPlayToEnd(try #require(player.currentItem))

        // Then
        #expect(finishedCount == 0)
    }

    @Test func ignoresEndOfOtherItems() async throws {
        // Given
        let view = VideoPlayerView()
        view.isLooping = false
        let asset = try await makeLongAsset()
        view.asset = asset
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()

        // When an item the view doesn't play ends, even one with the same asset
        postDidPlayToEnd(AVPlayerItem(asset: asset))

        // Then
        #expect(finishedCount == 0)
    }

    @Test func resetStopsReportingEnd() async throws {
        // Given
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeLongAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()
        let item = try #require(view.playerLayer.player?.currentItem)

        // When
        view.reset()
        postDidPlayToEnd(item)

        // Then
        #expect(finishedCount == 0)
    }

    @Test func settingAssetToNilStopsReportingEnd() async throws {
        // Given
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeLongAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()
        let item = try #require(view.playerLayer.player?.currentItem)

        // When
        view.asset = nil
        postDidPlayToEnd(item)

        // Then
        #expect(finishedCount == 0)
    }

    /// Regression test for https://github.com/kean/Nuke/issues/818: every
    /// `play()`/`reset()` cycle used to add another observer, so the end of
    /// a video was reported once per cycle.
    @Test func repeatedPlayAndResetReportEndOnce() async throws {
        // Given
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeLongAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        var previousItems: [AVPlayerItem] = []
        for _ in 0..<3 {
            view.play()
            previousItems.append(try #require(view.playerLayer.player?.currentItem))
            view.reset()
        }
        view.play()
        previousItems.append(try #require(view.playerLayer.player?.currentItem))
        view.play()
        let item = try #require(view.playerLayer.player?.currentItem)

        // When
        postDidPlayToEnd(item)

        // Then
        #expect(finishedCount == 1)

        // When the items the view no longer plays end
        for previousItem in previousItems {
            postDidPlayToEnd(previousItem)
        }

        // Then
        #expect(finishedCount == 1)
    }

    @Test func reportsEndOfNewAssetOnly() async throws {
        // Given
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeLongAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()
        let oldItem = try #require(view.playerLayer.player?.currentItem)

        // When
        view.asset = try await makeLongAsset()
        view.play()
        let newItem = try #require(view.playerLayer.player?.currentItem)
        postDidPlayToEnd(oldItem)

        // Then
        #expect(finishedCount == 0)

        // When
        postDidPlayToEnd(newItem)

        // Then
        #expect(finishedCount == 1)
    }
}

// MARK: - Playback

/// Plays short videos decoded by `ImageDecoders.Video` – the way the
/// documentation pairs the two – to the end.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct VideoPlayerViewPlaybackTests {
    let host = WindowHost()

    @Test func playsDecodedVideoToEndAndReportsFinish() async throws {
        // Given
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeShortAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        host.add(view)

        // When
        view.play()
        let player = try #require(view.playerLayer.player)
        try await waitUntil { finishedCount > 0 }

        // Then the player stops at the end
        #expect(finishedCount == 1)
        #expect(player.rate == 0)
        let item = try #require(player.currentItem)
        #expect(abs(item.currentTime().seconds - item.duration.seconds) < 0.05)
    }

    @Test func loopingVideoStartsOverWhenItEnds() async throws {
        // Given
        let view = VideoPlayerView()
        view.asset = try await makeShortAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        host.add(view)
        view.play()
        let player = try #require(view.playerLayer.player)
        let ends = EndOfItemCounter(item: try #require(player.currentItem))
        defer { ends.invalidate() }

        // When
        try await waitUntil { ends.count >= 2 }

        // Then the video reached its end again after the first time, so it
        // started over, and the view didn't report it as finished
        #expect(finishedCount == 0)
        #expect(player.rate != 0)
    }

    @Test func restartReplaysFinishedVideo() async throws {
        // Given a video that played to the end
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeShortAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()
        let player = try #require(view.playerLayer.player)
        try await waitUntil { finishedCount == 1 }

        // When
        view.restart()

        // Then it plays and finishes again
        #expect(player.rate != 0)
        try await waitUntil { finishedCount == 2 }
        #expect(player.rate == 0)
    }

    /// Turning looping on for a video that isn't playing starts it over.
    @Test func enablingLoopingRestartsFinishedVideo() async throws {
        // Given a video that played to the end
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeShortAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()
        let player = try #require(view.playerLayer.player)
        try await waitUntil { finishedCount == 1 }
        let ends = EndOfItemCounter(item: try #require(player.currentItem))
        defer { ends.invalidate() }

        // When
        view.isLooping = true

        // Then it plays again, and keeps playing past the end
        #expect(player.rate != 0)
        #expect(player.actionAtItemEnd == .none)
        try await waitUntil { ends.count >= 1 }
        #expect(finishedCount == 1)
    }

    @Test func disablingLoopingDuringPlaybackFinishesAtEnd() async throws {
        // Given a looping video that is playing
        let view = VideoPlayerView()
        view.asset = try await makeShortAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()
        let player = try #require(view.playerLayer.player)
        try await waitUntil { player.rate != 0 }

        // When
        view.isLooping = false

        // Then it doesn't restart it, and it stops at the end
        #expect(player.rate != 0)
        try await waitUntil { finishedCount == 1 }
        #expect(player.rate == 0)
    }

    /// `isLooping` only acts on a change: setting the current value doesn't
    /// resume a video that was paused.
    @Test func settingLoopingToSameValueDoesNotResumePausedVideo() async throws {
        // Given a looping video that was paused
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        view.play()
        let player = try #require(view.playerLayer.player)
        try await waitUntil { player.rate != 0 }
        player.pause()

        // When
        view.isLooping = true

        // Then
        #expect(player.rate == 0)
    }

    @Test func doesNotResumeNonLoopingVideoWhenAddedBackToWindow() async throws {
        // Given a video that doesn't loop, paused while out of the window
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeLongAsset()
        host.add(view)
        view.play()
        let player = try #require(view.playerLayer.player)
        try await waitUntil { player.rate != 0 }
        view.removeFromSuperview()
        player.pause()

        // When
        host.add(view)

        // Then
        #expect(player.rate == 0)
    }

    @Test func removingFromWindowDoesNotResumePausedVideo() async throws {
        // Given a looping video paused while in the window
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        host.add(view)
        view.play()
        let player = try #require(view.playerLayer.player)
        try await waitUntil { player.rate != 0 }
        player.pause()

        // When
        view.removeFromSuperview()

        // Then
        #expect(player.rate == 0)
    }

    /// Neither the status observation nor the notification observers keep the
    /// view or its player alive.
    @Test func viewAndPlayerAreReleasedAfterPlayback() async throws {
        // Given a view that is playing a video
        weak var weakView: VideoPlayerView?
        weak var weakPlayer: AVPlayer?
        var lastItem: AVPlayerItem?
        do {
            let view = VideoPlayerView()
            view.isLooping = false
            view.onVideoFinished = { Issue.record("The view was released") }
            view.asset = try await makeLongAsset()
            host.add(view)
            view.play()
            let player = try #require(view.playerLayer.player)
            try await waitUntil { player.rate != 0 }
            weakView = view
            weakPlayer = player
            lastItem = player.currentItem

            // When
            view.removeFromSuperview()
        }

        // Then
        try await waitUntil { weakView == nil && weakPlayer == nil }

        // Then the end of the item it played no longer reaches it
        postDidPlayToEnd(try #require(lastItem))
    }

    @Test func resetReleasesPlayer() async throws {
        // Given
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        view.play()
        weak var weakPlayer: AVPlayer?
        do {
            let player = try #require(view.playerLayer.player)
            try await waitUntil { player.rate != 0 }
            weakPlayer = player
        }

        // When
        view.reset()

        // Then
        try await waitUntil { weakPlayer == nil }
    }
}

// MARK: - Helpers

/// A 0.3 s video, decoded into an in-memory asset by `ImageDecoders.Video`.
private func makeShortAsset() async throws -> AVAsset {
    try await makeDecodedAsset(VideoFixture(width: 16, height: 16, frameCount: 9))
}

/// A 10 s video, long enough that playback can't reach the end while the test runs.
private func makeLongAsset() async throws -> AVAsset {
    try await makeDecodedAsset(VideoFixture(width: 16, height: 16, frameCount: 300))
}

private func makeDecodedAsset(_ fixture: VideoFixture) async throws -> AVAsset {
    let data = try await fixture.makeData()
    let decoder = try #require(ImageDecoders.Video(context: makeContext(data)))
    return try #require(decoder.decode(data).userInfo[.videoAssetKey] as? AVAsset)
}

@MainActor
private func postDidPlayToEnd(_ item: AVPlayerItem) {
    NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
}

@MainActor
private func sublayers(of view: VideoPlayerView) -> [CALayer] {
#if os(macOS)
    view.layer?.sublayers ?? []
#else
    view.layer.sublayers ?? []
#endif
}

@MainActor
private func layoutNow(_ view: VideoPlayerView) {
#if os(macOS)
    view.needsLayout = true
    view.layoutSubtreeIfNeeded()
#else
    view.setNeedsLayout()
    view.layoutIfNeeded()
#endif
}

/// Waits for a condition that AVFoundation only reaches asynchronously.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(30),
    _ condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting for the player", sourceLocation: sourceLocation)
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// Counts the times an item reaches its end.
@MainActor
private final class EndOfItemCounter {
    private(set) var count = 0
    private var token: (any NSObjectProtocol)?

    init(item: AVPlayerItem) {
        token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.count += 1
            }
        }
    }

    func invalidate() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

/// Records the implicit actions a layer looks up, and whether actions were
/// enabled at the time. A layer doesn't look them up at all when they're disabled.
private final class LayerActionRecorder: NSObject, CALayerDelegate {
    private(set) var enabledKeys: [String] = []

    func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
        if !CATransaction.disableActions() {
            enabledKeys.append(event)
        }
        return nil
    }
}

#endif

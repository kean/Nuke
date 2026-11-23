// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import AVFoundation
@testable import NukeVideo

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

        // Then the frame changes without looking up an action for it. UIKit
        // also looks up "onLayout" when it lays out the layer, which has
        // nothing to do with the frame.
        #expect(view.playerLayer.frame.size == CGSize(width: 50, height: 60))
        #expect(actions.enabledKeys.filter { $0 != "onLayout" }.isEmpty)
        withExtendedLifetime(actions) {}
    }

    @Test func playWithoutAssetDoesNothing() {
        // Given
        let view = VideoPlayerView()

        // When
        view.play()
        view.restart()
        // ...and the view is added to a window, which resumes a player the
        // view has, and there is none to resume
        let host = TestWindow()
        host.add(view)

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
        #expect(player.isMuted)
        #expect(!player.preventsDisplaySleepDuringVideoPlayback)
        await waitUntil { view.looper?.status == .ready }
        let queue = try #require(player as? AVQueuePlayer)
        let looper = try #require(view.looper)
        let currentItem = try #require(queue.currentItem)
        #expect(looper.loopingPlayerItems.contains { $0 === currentItem })
        #expect(currentItem.asset === asset)
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
        await waitUntil { view.looper?.status == .ready }

        // When/Then
        view.isLooping = false
        #expect(view.playerLayer.player === player)
        #expect(view.looper?.status == .cancelled)
        #expect(player.actionAtItemEnd == .pause)

        player.pause()
        view.isLooping = true
        await waitUntil { view.looper?.status == .ready }
        #expect(view.playerLayer.player !== player)
        #expect(player.rate == 0)
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
        await waitUntil { second.currentItem?.asset === asset }
        #expect(second.currentItem?.asset === asset)
    }

    @Test func replacesPlaybackWhileDurationIsLoading() async throws {
        let view = VideoPlayerView()
        let loader = PendingResourceLoader()
        let first = AVURLAsset(url: try #require(URL(string: "nuke-test://pending/video.mp4")))
        first.resourceLoader.setDelegate(loader, queue: .main)
        let second = try await makeLongAsset()
        view.asset = first
        view.play()
        let superseded = try #require(view.playerLayer.player)
        await waitUntil { loader.request != nil }
        #expect(superseded.currentItem == nil)

        view.asset = second
        view.play()
        let player = try #require(view.playerLayer.player)
        loader.request?.finishLoading(with: CocoaError(.fileReadUnknown))
        await waitUntil { view.looper?.status == .ready }

        #expect(view.playerLayer.player === player)
        #expect(player.currentItem?.asset === second)
        #expect(superseded.currentItem == nil)
        #expect(superseded.rate == 0)
    }

    @Test func resetWhileDurationIsLoadingDiscardsPendingPlayback() async throws {
        let view = VideoPlayerView()
        let asset = try await makeLongAsset()
        view.asset = asset
        view.play()
        let player = try #require(view.playerLayer.player)
        #expect(player.currentItem == nil)

        view.reset()
        _ = try await asset.load(.duration)

        #expect(view.playerLayer.player == nil)
        #expect(view.looper == nil)
        #expect(player.currentItem == nil)
        #expect(player.rate == 0)
        #expect(view.asset === asset)
    }

    @Test func disablingLoopingWhileDurationIsLoadingStartsOneShotPlayback() async throws {
        let view = VideoPlayerView()
        let asset = try await makeShortAsset()
        view.asset = asset
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()
        let player = try #require(view.playerLayer.player)
        #expect(player.currentItem == nil)

        view.isLooping = false
        await waitUntil { finishedCount == 1 }

        #expect(view.playerLayer.player === player)
        #expect(player.currentItem?.asset === asset)
        #expect(player.rate == 0)
        #expect(view.looper == nil)
    }

    @Test func zeroDurationAssetUsesSingleItemPlayback() async throws {
        let view = VideoPlayerView()
        let asset = AVMutableComposition()
        #expect(try await asset.load(.duration) == .zero)
        view.asset = asset

        view.play()

        let player = try #require(view.playerLayer.player as? AVQueuePlayer)
        try #require(player.items().count == 1)
        #expect(player.currentItem?.asset === asset)
        #expect(view.looper == nil)
    }

    @Test func unreadableAssetDoesNotCreateLooper() async throws {
        let view = VideoPlayerView()
        let asset = AVURLAsset(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4"))
        view.asset = asset
        view.onVideoFinished = { Issue.record("An unreadable asset cannot finish playing") }

        view.play()

        let player = try #require(view.playerLayer.player)
        await waitUntil { player.currentItem?.status == .failed }
        #expect(view.looper == nil)
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
        view.restart()
        #expect(view.playerLayer.player == nil)
        view.play()
        await waitUntil { view.playerLayer.player?.currentItem?.asset === asset }
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
        await waitUntil { view.looper?.status == .ready }

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
    let host = TestWindow()

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
        await waitUntil { finishedCount > 0 }

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
        await waitUntil { view.looper?.status == .ready }
        let looper = try #require(view.looper)
        let firstItem = try #require(player.currentItem)

        await waitUntil { looper.loopCount >= 1 }
        #expect(player.currentItem !== firstItem)
        await waitUntil { looper.loopCount >= 2 }
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
        await waitUntil { finishedCount == 1 }

        // When
        view.restart()

        // Then it plays and finishes again
        #expect(player.rate != 0)
        await waitUntil { finishedCount == 2 }
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
        await waitUntil { finishedCount == 1 }
        // When
        view.isLooping = true

        // Then it plays again, and keeps playing past the end
        await waitUntil { (view.looper?.loopCount ?? 0) >= 2 }
        #expect(view.playerLayer.player?.rate != 0)
        #expect(player.rate == 0)
        #expect(finishedCount == 1)
    }

    @Test func disablingLoopingDuringPlaybackFinishesAtEnd() async throws {
        // Given a looping video that is playing
        let view = VideoPlayerView()
        view.asset = try await makeShortAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()
        let player = try #require(view.playerLayer.player as? AVQueuePlayer)
        await waitUntil { (view.looper?.loopCount ?? 0) >= 1 }
        let item = try #require(player.currentItem)
        let otherReplica = try #require(view.looper?.loopingPlayerItems.first { $0 !== item })

        // When
        view.isLooping = false
        postDidPlayToEnd(otherReplica)

        // Then the current replica finishes without playing any more replicas
        #expect(finishedCount == 0)
        #expect(player.currentItem === item)
        #expect(player.rate != 0)
        await waitUntil { finishedCount == 1 }
        #expect(player.rate == 0)
        #expect(player.currentItem === item)
        #expect(player.items() == [item])
        #expect(item.currentTime() == item.duration)
        postDidPlayToEnd(item)
        #expect(finishedCount == 1)
    }

    @Test func enablingLoopingWhilePlayingWaitsForCurrentItem() async throws {
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeShortAsset()
        var finishedCount = 0
        view.onVideoFinished = { finishedCount += 1 }
        view.play()
        let firstPlayer = try #require(view.playerLayer.player)
        let firstItem = try #require(firstPlayer.currentItem)
        await waitUntil { firstItem.currentTime() > .zero && firstPlayer.rate != 0 }

        view.isLooping = true

        #expect(view.playerLayer.player === firstPlayer)
        #expect(firstPlayer.currentItem === firstItem)
        await waitUntil { (view.looper?.loopCount ?? 0) >= 2 }
        #expect(firstItem.currentTime() == firstItem.duration)
        #expect(firstPlayer.rate == 0)
        #expect(finishedCount == 0)
    }

    @Test func restartDuringLoopingStartsFreshReplicasFromTheBeginning() async throws {
        let view = VideoPlayerView()
        view.asset = try await makeShortAsset()
        view.onVideoFinished = { Issue.record("Restarting a looping video cannot finish it") }
        view.play()
        await waitUntil { (view.looper?.loopCount ?? 0) >= 1 }
        let oldPlayer = try #require(view.playerLayer.player)
        let oldLooper = try #require(view.looper)

        view.restart()

        #expect(oldPlayer.rate == 0)
        #expect(oldLooper.status == .cancelled)
        #expect(view.playerLayer.player !== oldPlayer)
        let looper = try #require(view.looper)
        #expect(looper !== oldLooper)
        #expect(looper.loopCount == 0)
        await waitUntil { looper.loopCount >= 2 }
    }

    /// `isLooping` only acts on a change: setting the current value doesn't
    /// resume a video that was paused.
    @Test func settingLoopingToSameValueDoesNotResumePausedVideo() async throws {
        // Given a looping video that was paused
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        view.play()
        let player = try #require(view.playerLayer.player)
        await waitUntil { player.rate != 0 }
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
        await waitUntil { player.rate != 0 }
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
        await waitUntil { player.rate != 0 }
        player.pause()

        // When
        view.removeFromSuperview()

        // Then
        #expect(player.rate == 0)
    }

    @Test func doesNotResumeVideoPausedBeforeWindowRemoval() async throws {
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        host.add(view)
        view.play()
        let player = try #require(view.playerLayer.player)
        await waitUntil { player.rate != 0 }
        player.pause()

        view.removeFromSuperview()
        host.add(view)

        #expect(player.rate == 0)
    }

    /// The end observer does not keep the view or its player alive.
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
            await waitUntil { player.rate != 0 }
            weakView = view
            weakPlayer = player
            lastItem = player.currentItem

            // When
            view.removeFromSuperview()
        }

        // Then
        await waitUntil { weakView == nil && weakPlayer == nil }

        // Then the end of the item it played no longer reaches it
        postDidPlayToEnd(try #require(lastItem))
    }

    @Test func releasingViewDetachesRetainedLayerAndReleasesLooper() async throws {
        weak var weakView: VideoPlayerView?
        weak var weakPlayer: AVPlayer?
        weak var weakLooper: AVPlayerLooper?
        let layer: AVPlayerLayer
        do {
            let view = VideoPlayerView()
            view.asset = try await makeShortAsset()
            view.play()
            await waitUntil { view.looper?.status == .ready }
            weakView = view
            weakPlayer = view.playerLayer.player
            let looper = try #require(view.looper)
            weakLooper = looper
            layer = view.playerLayer
        }

        await waitUntil { weakView == nil && weakPlayer == nil && weakLooper == nil }
        #expect(layer.player == nil)
    }

    @Test func resetReleasesPlayer() async throws {
        // Given
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        view.play()
        weak var weakPlayer: AVPlayer?
        weak var weakLooper: AVPlayerLooper?
        weak var weakItem: AVPlayerItem?
        do {
            let player = try #require(view.playerLayer.player)
            await waitUntil { view.looper?.status == .ready }
            weakPlayer = player
            let looper = try #require(view.looper)
            let item = try #require(player.currentItem)
            weakLooper = looper
            weakItem = item
        }

        // When
        view.reset()

        // Then
        await waitUntil { weakPlayer == nil && weakLooper == nil && weakItem == nil }
    }
}

// MARK: - Foreground

#if os(iOS) || os(tvOS)
/// The system pauses the videos of an app in the background, and a looping one
/// resumes when the app comes back. The view observes the notification from
/// any object, so these tests post it one at a time.
@Suite(.serialized, .timeLimit(.minutes(5))) @MainActor
struct VideoPlayerViewForegroundTests {
    let host = TestWindow()

    @Test func resumesLoopingVideoWhenAppEntersForeground() async throws {
        // Given a looping video that was paused while the app was in the
        // background
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        host.add(view)
        view.play()
        let player = try #require(view.playerLayer.player)
        await waitUntil { player.rate != 0 }
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        player.pause()

        // When
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Then
        #expect(player.rate != 0)
    }

    @Test func doesNotResumeNonLoopingVideoWhenAppEntersForeground() async throws {
        // Given a video that doesn't loop, paused while the app was in the
        // background
        let view = VideoPlayerView()
        view.isLooping = false
        view.asset = try await makeLongAsset()
        host.add(view)
        view.play()
        let player = try #require(view.playerLayer.player)
        await waitUntil { player.rate != 0 }
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        player.pause()

        // When
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Then
        #expect(player.rate == 0)
    }

    @Test func doesNotResumeVideoPausedBeforeLeavingForeground() async throws {
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        host.add(view)
        view.play()
        let player = try #require(view.playerLayer.player)
        await waitUntil { player.rate != 0 }
        player.pause()

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        #expect(player.rate == 0)
    }

    @Test func doesNotResumeTheVideoOfAViewResetInTheBackground() async throws {
        // Given a looping video that was paused while the app was in the
        // background, and a view that was reset since
        let view = VideoPlayerView()
        view.asset = try await makeLongAsset()
        host.add(view)
        view.play()
        let player = try #require(view.playerLayer.player)
        await waitUntil { player.rate != 0 }
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        player.pause()
        view.reset()

        // When
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Then
        #expect(player.rate == 0)
    }
}
#endif

// MARK: - Helpers

/// Holds a read so a test can replace an asset during duration loading.
@MainActor
private final class PendingResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private(set) var request: AVAssetResourceLoadingRequest?

    nonisolated func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        MainActor.assumeIsolated {
            request = loadingRequest
        }
        return true
    }
}

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
    let decoder = try #require(ImageDecoders.Video(context: .mock(data: data)))
    return try #require(decoder.decode(data).userInfo[.videoAssetKey] as? AVAsset)
}

@MainActor
private func postDidPlayToEnd(_ item: AVPlayerItem) {
    NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: item)
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

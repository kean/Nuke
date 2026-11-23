// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import AVKit
import Foundation

#if !os(watchOS)

#if os(macOS)
public typealias _PlatformBaseView = NSView
#else
public typealias _PlatformBaseView = UIView
#endif

/// A view that plays video content using AVKit.
///
/// Use ``asset`` to set the video to play and ``play()`` to start playback.
/// The view loops video by default and is muted.
@MainActor
public final class VideoPlayerView: _PlatformBaseView {
    // MARK: Configuration

    /// The video gravity. `.resizeAspectFill` by default.
    public var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet {
            _playerLayer?.videoGravity = videoGravity
        }
    }

    /// `true` by default. If disabled, the video will resize with the frame without animations.
    public var animatesFrameChanges = true

    /// `true` by default. Turning looping off lets the current iteration finish.
    /// Turning it on during playback starts looping after the current item ends.
    public var isLooping = true {
        didSet {
            guard isLooping != oldValue else { return }
            updateLooping()
        }
    }

    /// A closure called when a video finishes playing with looping disabled.
    public var onVideoFinished: (() -> Void)?

    // MARK: Initialization

    /// The underlying player layer. Created lazily on first access.
    public var playerLayer: AVPlayerLayer {
        if let layer = _playerLayer {
            return layer
        }
        let playerLayer = AVPlayerLayer()
#if os(macOS)
        wantsLayer = true
        self.layer?.addSublayer(playerLayer)
#else
        self.layer.addSublayer(playerLayer)
#endif
        playerLayer.frame = bounds
        playerLayer.videoGravity = videoGravity
        _playerLayer = playerLayer
        return playerLayer
    }

    private var _playerLayer: AVPlayerLayer?

#if os(iOS) || os(tvOS) || os(visionOS)
    override public func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(!animatesFrameChanges)
        _playerLayer?.frame = bounds
        CATransaction.commit()
    }
#elseif os(macOS)
    override public func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(!animatesFrameChanges)
        _playerLayer?.frame = bounds
        CATransaction.commit()
    }
#endif

    // MARK: Playback

    private var player: AVQueuePlayer?
    private var playbackAsset: AVAsset?
    private var preparation: Task<Void, Never>?
    private(set) var looper: AVPlayerLooper?
    private var loopsAfterCurrentItem = false
    private var wasPlayingBeforeLeavingWindow = false
    private var wasPlayingBeforeLeavingForeground = false

    private var finishObservationID = 0
    private var finishObserver: (any NSObjectProtocol)? {
        didSet {
            if let oldValue {
                NotificationCenter.default.removeObserver(oldValue)
            }
        }
    }

    isolated deinit {
        reset()
    }

    /// Stops playback and removes the current player, releasing associated resources.
    public func reset() {
        preparation?.cancel()
        preparation = nil
        finishObserver = nil
#if os(iOS) || os(tvOS) || os(visionOS)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
#endif
        player?.pause()
        if let looper, looper.status != .cancelled {
            looper.disableLooping()
        }
        _playerLayer?.player = nil
        looper = nil
        player = nil
        playbackAsset = nil
        loopsAfterCurrentItem = false
        wasPlayingBeforeLeavingWindow = false
        wasPlayingBeforeLeavingForeground = false
    }

    /// The video asset to play. Setting a new asset prepares the view for playback;
    /// call ``play()`` to start.
    public var asset: AVAsset? {
        didSet {
            if asset == nil || (preparation != nil && oldValue !== asset) {
                reset()
            }
        }
    }

    /// Returns to the beginning and resumes playback.
    public func restart() {
        guard let player, let playbackAsset, preparation == nil else { return }
        if !isLooping, looper == nil, let item = player.currentItem {
            observeEnd(of: item, in: player)
            player.seek(to: .zero)
            player.play()
        } else {
            play(playbackAsset)
        }
    }

    /// Creates a player for the current ``asset`` and starts playback.
    ///
    /// The video is muted and set to loop by default. Looping waits for the asset's
    /// duration to load. Assets without a known, positive duration use single-item playback.
    public func play() {
        guard let asset else { return }
        play(asset)
    }

    private func play(_ asset: AVAsset) {
        reset()

        let player = AVQueuePlayer()
        player.isMuted = true
#if os(visionOS)
        player.preventsAutomaticBackgroundingDuringVideoPlayback = false
#else
        player.preventsDisplaySleepDuringVideoPlayback = false
#endif
        player.actionAtItemEnd = .pause
        self.player = player
        playbackAsset = asset
        playerLayer.player = player

#if os(iOS) || os(tvOS) || os(visionOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
#endif

        if !isLooping {
            playOnce(asset, in: player)
        } else if case .loaded(let duration) = asset.status(of: .duration) {
            startLooping(asset, duration: duration, in: player)
        } else {
            preparation = Task { [weak self, weak player] in
                guard !Task.isCancelled else { return }
                let duration = try? await asset.load(.duration)
                guard !Task.isCancelled, let self, let player, self.player === player else { return }
                preparation = nil
                startLooping(asset, duration: duration, in: player)
            }
        }
    }

    private func startLooping(_ asset: AVAsset, duration: CMTime?, in player: AVQueuePlayer) {
        guard let duration, duration.isNumeric, duration > .zero else {
            playOnce(asset, in: player)
            return
        }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
        player.play()
    }

    private func playOnce(_ asset: AVAsset, in player: AVQueuePlayer) {
        let item = AVPlayerItem(asset: asset)
        player.insert(item, after: nil)
        observeEnd(of: item, in: player)
        player.play()
    }

    private func updateLooping() {
        guard let player, let playbackAsset else { return }
        if isLooping {
            if finishObserver != nil && player.wantsToPlay {
                // Let the current one-shot item finish at its existing position.
                // A fresh queue can then start at the beginning with only replicas.
                loopsAfterCurrentItem = true
            } else {
                play(playbackAsset)
            }
        } else {
            loopsAfterCurrentItem = false
            if preparation != nil {
                preparation?.cancel()
                preparation = nil
                playOnce(playbackAsset, in: player)
            } else if let looper, looper.status != .cancelled {
                looper.disableLooping()
                // Keep the looper until this queue is replaced. Releasing it
                // while the last replica is playing can remove that replica.
                player.actionAtItemEnd = .pause
                if let item = player.currentItem {
                    observeEnd(of: item, in: player)
                }
            }
        }
    }

    private func observeEnd(of item: AVPlayerItem, in player: AVQueuePlayer) {
        finishObservationID &+= 1
        let id = finishObservationID
        finishObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self, weak player, weak item] _ in
            MainActor.assumeIsolated {
                guard let self, let player, let item,
                      self.finishObservationID == id, self.finishObserver != nil,
                      self.player === player, player.currentItem === item else { return }
                self.finishObserver = nil
                if self.loopsAfterCurrentItem, let playbackAsset = self.playbackAsset {
                    self.play(playbackAsset)
                } else if !self.isLooping {
                    self.onVideoFinished?()
                }
            }
        }
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    @objc private func applicationWillResignActive() {
        wasPlayingBeforeLeavingForeground = player?.wantsToPlay == true
    }

    @objc private func applicationWillEnterForeground() {
        let wasPlaying = wasPlayingBeforeLeavingForeground
        wasPlayingBeforeLeavingForeground = false
        resumeAfterInterruption(if: wasPlaying)
    }

    override public func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        updateWindow(isAttached: newWindow != nil)
    }
#elseif os(macOS)
    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        updateWindow(isAttached: newWindow != nil)
    }
#endif

    private func updateWindow(isAttached: Bool) {
        if isAttached {
            let wasPlaying = wasPlayingBeforeLeavingWindow
            wasPlayingBeforeLeavingWindow = false
            resumeAfterInterruption(if: wasPlaying)
        } else {
            wasPlayingBeforeLeavingWindow = player?.wantsToPlay == true
        }
    }

    private func resumeAfterInterruption(if wasPlaying: Bool) {
        if wasPlaying, isLooping, let player, player.status == .readyToPlay, !player.wantsToPlay {
            player.play()
        }
    }
}

@MainActor
private extension AVPlayer {
    var wantsToPlay: Bool {
        timeControlStatus != .paused && error == nil
    }
}

#endif

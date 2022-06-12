// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import AVKit
import Foundation

#if !os(watchOS)

public final class VideoPlayerView: _PlatformBaseView {
    // MARK: Configuration

    /// `.resizeAspectFill` by default.
    public var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }

    /// `true` by default. If disabled, will only play a video once.
    public var isLooping = true {
        didSet {
            player?.actionAtItemEnd = isLooping ? .none : .pause
            if isLooping, !(player?.nowPlaying ?? false) {
                restart()
            }
        }
    }
    
    /// Add if you want to do something at the end of the video
    var onVideoFinished: (() -> Void)?

    // MARK: Initialization
    #if !os(macOS)
    public override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        (layer as? AVPlayerLayer) ?? AVPlayerLayer() // The right side should never happen
    }
    #else
    public let playerLayer = AVPlayerLayer()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // Creating a view backed by a custom layer on macOS is ... hard
        wantsLayer = true
        layer?.addSublayer(playerLayer)
        playerLayer.frame = bounds
    }

    public override func layout() {
        super.layout()

        playerLayer.frame = bounds
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    #endif

    // MARK: Private
    
    private var player: AVPlayer? {
        didSet {
            registerNotification()
        }
    }
    
    private var playerObserver: AnyObject?

    public func reset() {
        playerLayer.player = nil
        player = nil
        playerObserver = nil
    }

    public var asset: AVAsset? {
        didSet { assetDidChange() }
    }

    private func assetDidChange() {
        if asset == nil {
            reset()
        }
    }
    
    private func registerNotification() {
        NotificationCenter.default
            .addObserver(self,
                         selector: #selector(registerNotification(_:)),
                         name: .AVPlayerItemDidPlayToEndTime,
                         object: player?.currentItem)
    }
    
    public func restart() {
        player?.seek(to: CMTime.zero)
        player?.play()
    }
    
    public func play() {
        guard let asset = asset else {
            return
        }

        let playerItem = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(playerItem: playerItem)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = isLooping ? .none : .pause
        self.player = player

        playerLayer.player = player

        playerObserver = player.observe(\.status, options: [.new, .initial]) { player, change in
            if player.status == .readyToPlay {
                player.play()
            }
        }
    }
    
    @objc private func registerNotification(_ notification: Notification) {
        guard let playerItem = notification.object as? AVPlayerItem else {
            return
        }
        
        if isLooping {
            playerItem.seek(to: CMTime.zero, completionHandler: nil)
        } else {
            onVideoFinished?()
        }
    }
}

extension AVLayerVideoGravity {
    init(_ contentMode: ImageResizingMode) {
        switch contentMode {
        case .aspectFit: self = .resizeAspect
        case .aspectFill: self = .resizeAspectFill
        case .center: self = .resizeAspect
        case .fill: self = .resize
        }
    }
}

extension AVPlayer {
    var nowPlaying: Bool {
        return rate != 0 && error == nil
    }
}

#endif

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// An image view that plays animated images.
///
/// It is a drop-in replacement for the platform image view: everything that
/// works with `UIImageView` or `NSImageView` – content modes, layout, the
/// ``loadImage(with:options:into:completion:)-(URL?,_,_,_)`` extensions – works
/// with it, and an image that turns out to be animated plays instead of showing
/// its first frame.
///
/// ```swift
/// let imageView = AnimatedImageView()
/// NukeUI.loadImage(with: url, into: imageView)
/// ```
///
/// Set ``animatedImage`` to play an image you already have:
///
/// ```swift
/// imageView.animatedImage = AnimatedImageSource(data: data)
/// ```
///
/// The view plays only while it is in a window, so an animation in a cell that
/// scrolls out of view stops decoding frames and starts again when it comes
/// back. ``player`` exposes the playback controls and the diagnostics.
@MainActor
public final class AnimatedImageView: _PlatformImageView {
    /// The image being played, or `nil` if the view is showing a still image.
    ///
    /// Setting it replaces the current animation and starts playing, unless
    /// ``isPlaybackEnabled`` is off.
    public var animatedImage: AnimatedImageSource? {
        get { _animatedImage }
        set {
            cancelPendingParse()
            setAnimatedImage(newValue, scale: scale(of: image))
        }
    }

    /// The player driving ``animatedImage``, or `nil` when there is nothing to
    /// play.
    ///
    /// A new one is created every time ``animatedImage`` is set. Assign your
    /// own to control playback from outside the view or to read
    /// ``AnimatedImagePlayer/diagnostics`` – the view starts and stops it as it
    /// moves in and out of a window, exactly as it does its own.
    public var player: AnimatedImagePlayer? {
        didSet {
            guard oldValue !== player else { return }
            // A player set from outside wins over anything on its way.
            cancelPendingParse()
            sourcePendingDownsampling = nil
            oldValue?.pause()
            oldValue?.onFrame = nil
            _animatedImage = player?.source
            player?.onFrame = { [weak self] in self?.image = $0 }
            if let image = player?.image {
                self.image = image
            }
            updatePlaybackState()
        }
    }

    private var _animatedImage: AnimatedImageSource?

    /// The parse in flight, if any. Exists for the tests.
    var pendingParse: Task<Void, Never>?

    /// The animation whose frames are being decoded at full size because the
    /// view had no size of its own to scale them to yet.
    private var sourcePendingDownsampling: AnimatedImageSource?

    /// The options the view creates its players with.
    ///
    /// Changing them takes effect the next time ``animatedImage`` is set.
    public var playerOptions = AnimatedImagePlayer.Options()

    /// Whether animations play. `true` by default.
    ///
    /// Set it to `false` to show the first frame of every animated image as a
    /// still – which is what a table full of animations should do while the
    /// user is deciding whether they want to see them move.
    public var isPlaybackEnabled = true {
        didSet {
            guard isPlaybackEnabled != oldValue else { return }
            updatePlaybackState()
        }
    }

    /// Whether playback pauses while the view is not in a window. `true` by
    /// default.
    public var isPlaybackPausedWhenOffscreen = true {
        didSet {
            guard isPlaybackPausedWhenOffscreen != oldValue else { return }
            updatePlaybackState()
        }
    }

    /// Whether the frames are decoded no larger than the view displays them.
    /// `true` by default.
    ///
    /// It is the largest memory win there is: a 1000-pixel animation costs
    /// 4 MB a frame, and the same animation decoded for a 120-point cell costs
    /// 0.2 MB. The frames are never scaled up, so an animation that is already
    /// smaller than the view is decoded as it is.
    ///
    /// Set ``AnimatedImagePlayer/Options/maxPixelSize`` in ``playerOptions`` to
    /// pick the size yourself; it wins over this. Set this to `false` to decode
    /// every animation at full size – a view that is going to grow, say.
    public var isAutomaticDownsamplingEnabled = true

    /// `true` while the animation is running.
    ///
    /// Deliberately not `UIImageView.isAnimating`: that property belongs to the
    /// view's own `animationImages` playback, and a view that claims to be
    /// running one stops displaying `image` at all.
    public var isPlaying: Bool { player?.isPlaying ?? false }

#if os(macOS)
    // `NSImageView.animates` is on by default, and a multi-frame `NSImage`
    // under it plays on AppKit's own timer: the poster frame would animate
    // beside the player, and a view with `isPlaybackEnabled` off would animate
    // a picture it is meant to be holding still.

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        animates = false
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        animates = false
    }
#endif

    // MARK: Displaying Images

    /// Displays the image, playing it if the pipeline recognized it as animated.
    ///
    /// This is the entry point the ``loadImage(with:options:into:completion:)-(URL?,_,_,_)``
    /// extensions use. The `image` argument is the still frame the decoder
    /// produced, which is displayed immediately, and the animation – if there
    /// is one – takes over as soon as its first frame is decoded.
#if os(macOS)
    override public func nuke_display(image: NSImage?, data: Data?) {
        display(image: image, data: data)
    }
#else
    override public func nuke_display(image: UIImage?, data: Data?) {
        display(image: image, data: data)
    }
#endif

    private func display(image: PlatformImage?, data: Data?) {
        // The scale has to be passed in rather than read back from the view:
        // `self.image` is still whatever the view was showing before this call.
        let scale = scale(of: image)
        cancelPendingParse()
        // An animation seen before is parsed before this returns, so setting it
        // first is what keeps a fast decode from being covered by the poster
        // frame. One that has to be parsed lands later, and the poster is what
        // holds the place until it does.
        if let data {
            pendingParse = AnimatedImageSource.parse(data: data) { [weak self] source in
                self?.setAnimatedImage(source, scale: scale)
            }
        } else {
            setAnimatedImage(nil, scale: scale)
        }
        if animatedImage == nil || player?.image == nil {
            self.image = image
        }
    }

    private func cancelPendingParse() {
        pendingParse?.cancel()
        pendingParse = nil
    }

    /// Stops the animation and clears the view.
#if os(macOS)
    override public func prepareForReuse() {
        super.prepareForReuse()
        reset()
    }
#else
    public func prepareForReuse() {
        reset()
    }
#endif

    private func reset() {
        animatedImage = nil
        image = nil
    }

    // MARK: Layout

    // A view that is given an animation before it is laid out – a cell, and
    // every SwiftUI view, which has no size at all when it is made – can't know
    // what to decode the frames for. It decodes them at full size and settles
    // it here, at the first layout with a size, and only for an animation that
    // is actually bigger than the view: the rebuild costs a decode, and there
    // is nothing to win when the frames are already small enough.

#if os(macOS)
    override public func layout() {
        super.layout()
        applyAutomaticDownsamplingIfNeeded()
    }
#else
    override public func layoutSubviews() {
        super.layoutSubviews()
        applyAutomaticDownsamplingIfNeeded()
    }
#endif

    private func applyAutomaticDownsamplingIfNeeded() {
        guard let source = sourcePendingDownsampling,
              let maxPixelSize = automaticMaxPixelSize else { return }
        sourcePendingDownsampling = nil
        guard maxPixelSize < max(source.size.width, source.size.height) else {
            return
        }
        setPlayer(for: source, scale: player?.options.scale, maxPixelSize: maxPixelSize)
    }

    /// The longest side, in pixels, the frames need to fill this view, or `nil`
    /// when the view has no size or is decoding at a size it was given.
    private var automaticMaxPixelSize: CGFloat? {
        guard wantsAutomaticDownsampling else { return nil }
        let side = max(bounds.width, bounds.height)
        guard side > 0 else { return nil }
#if os(macOS)
        let scale = window?.backingScaleFactor ?? 2
#else
        let scale = contentScaleFactor
#endif
        return side * max(scale, 1)
    }

    private var wantsAutomaticDownsampling: Bool {
        isAutomaticDownsamplingEnabled && playerOptions.maxPixelSize == nil
    }

    // MARK: Window Changes

#if os(macOS)
    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePlaybackState()
    }
#else
    override public func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlaybackState()
    }
#endif

    // MARK: Private

    private func setAnimatedImage(_ source: AnimatedImageSource?, scale: CGFloat?) {
        guard _animatedImage !== source else { return }
        _animatedImage = source
        let maxPixelSize = automaticMaxPixelSize
        setPlayer(for: source, scale: scale, maxPixelSize: maxPixelSize)
        // Set after the player, whose `didSet` clears it: this is the animation
        // the next layout has to settle a size for.
        sourcePendingDownsampling = maxPixelSize == nil && wantsAutomaticDownsampling ? source : nil
    }

    private func setPlayer(for source: AnimatedImageSource?, scale: CGFloat?, maxPixelSize: CGFloat?) {
        player = source.map { source in
            var options = playerOptions
            // Match the scale of the still image the decoder produced, or the
            // animation changes size the moment it starts playing.
            if options.scale == 1, let scale, scale != 1 {
                options.scale = scale
            }
            if options.maxPixelSize == nil {
                options.maxPixelSize = maxPixelSize
            }
            return AnimatedImagePlayer(source: source, options: options)
        }
    }

    /// The scale of the image the animation is replacing, or `nil` where the
    /// platform image has none.
    private func scale(of image: PlatformImage?) -> CGFloat? {
#if canImport(UIKit)
        image?.scale
#else
        nil
#endif
    }

    private func updatePlaybackState() {
        guard let player else { return }
        let isOnScreen = window != nil || !isPlaybackPausedWhenOffscreen
        if isPlaybackEnabled && isOnScreen {
            player.play()
        } else {
            player.pause()
            if !isOnScreen {
                // Nobody is watching, so the window of decoded frames is a
                // memory budget spent on frames nobody will see. A player
                // paused in place keeps them: resuming shouldn't stall.
                player.keepsFullBuffer = false
            }
        }
    }
}

#endif

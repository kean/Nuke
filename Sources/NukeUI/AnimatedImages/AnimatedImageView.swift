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
        set { setAnimatedImage(newValue, scale: scale(of: image)) }
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

    /// `true` while the animation is running.
    ///
    /// Deliberately not `UIImageView.isAnimating`: that property belongs to the
    /// view's own `animationImages` playback, and a view that claims to be
    /// running one stops displaying `image` at all.
    public var isPlaying: Bool { player?.isPlaying ?? false }

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
        // Setting `animatedImage` first would show the poster frame after the
        // animation has already started on a fast decode. The scale has to be
        // passed in rather than read back from the view: `self.image` is still
        // whatever the view was showing before this call.
        setAnimatedImage(data.flatMap(AnimatedImageSource.cached(data:)), scale: scale(of: image))
        if animatedImage == nil || player?.image == nil {
            self.image = image
        }
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
        player = source.map { makePlayer(for: $0, scale: scale) }
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

    private func makePlayer(for source: AnimatedImageSource, scale: CGFloat?) -> AnimatedImagePlayer {
        var options = playerOptions
        // Match the scale of the still image the decoder produced, or the
        // animation changes size the moment it starts playing.
        if options.scale == 1, let scale, scale != 1 {
            options.scale = scale
        }
        return AnimatedImagePlayer(source: source, options: options)
    }

    private func updatePlaybackState() {
        guard let player else { return }
        let shouldPlay = isPlaybackEnabled && (window != nil || !isPlaybackPausedWhenOffscreen)
        if shouldPlay {
            player.play()
        } else {
            player.pause()
        }
    }
}

#endif

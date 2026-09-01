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
/// The view plays only while it is on screen – in a window, not hidden, not
/// transparent – so an animation in a cell that scrolls out of view stops
/// decoding frames and starts again when it comes back. ``player`` exposes the
/// playback controls and the diagnostics.
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
    /// ``AnimatedImagePlayer/diagnostics``; the view starts and stops it as it
    /// moves in and out of a window, exactly as it does its own.
    public var player: AnimatedImagePlayer? {
        didSet {
            guard oldValue !== player else { return }
            // A player set from outside wins over anything on its way.
            sourcePendingDownsampling = nil
            oldValue?.pause()
            oldValue?.onFrameForDisplay = nil
            _animatedImage = player?.source
            // `image` rather than `layer.contents`, which would go around the
            // content modes and the aspect-fill drawing. Setting it does
            // invalidate the intrinsic content size on every frame, but frames
            // of one size trigger no layout pass: measured over 2000 frames,
            // zero layout passes and 8µs a frame against 0.2µs for
            // `layer.contents`. Frames whose size changes cost 55-99µs each
            // and a layout pass every one.
            player?.onFrameForDisplay = { [weak self] in self?.setImageKeepingAnimation($0) }
            if let image = player?.image {
                setImageKeepingAnimation(image)
            }
            updatePlaybackState()
        }
    }

    private var _animatedImage: AnimatedImageSource?

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
    /// still, which is what a table full of animations should do until the
    /// user asks to see them move.
    ///
    /// It is also the hook for Accessibility › Motion › Auto-Play Animated
    /// Images. Only SwiftUI publishes that setting, so ``AnimatedImage`` reads
    /// it and sets this itself; a view used directly has to be told.
    public var isPlaybackEnabled = true {
        didSet {
            guard isPlaybackEnabled != oldValue else { return }
            updatePlaybackState()
        }
    }

    /// Whether playback pauses while the view is not on screen – outside a
    /// window, hidden, or fully transparent. `true` by default.
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
    /// 0.2 MB. The frames are never scaled up.
    ///
    /// Set ``AnimatedImagePlayer/Options/maxPixelSize`` in ``playerOptions`` to
    /// pick the size yourself; it wins over this. Set this to `false` to decode
    /// every animation at full size – for a view that is going to grow, say.
    public var isAutomaticDownsamplingEnabled = true

#if os(macOS)
    /// Whether the frames cover the view, with whatever hangs over the edge
    /// clipped. `false` by default.
    ///
    /// `NSImageView` has no aspect-fill scaling mode – ``imageScaling`` only
    /// ever fits the image inside the view – so this is how you get on macOS
    /// what `UIView.ContentMode.scaleAspectFill` gives everywhere else. The
    /// view draws the frames itself while it is on, which is what
    /// ``AnimatedImage/resizable(contentMode:)`` uses for `.fill`.
    public var isAspectFillEnabled = false {
        didSet {
            guard isAspectFillEnabled != oldValue else { return }
            needsDisplay = true
        }
    }
#endif

    /// `true` while the animation is running.
    ///
    /// Deliberately not `UIImageView.isAnimating`: that property belongs to the
    /// view's own `animationImages` playback, and a view that claims to be
    /// running one stops displaying `image` at all.
    public var isPlaying: Bool { player?.isPlaying ?? false }

    /// Creates a view with a zero frame.
    ///
    /// Spelled out because a class that overrides the designated initializers
    /// inherits no `init()` from the platform image view.
    public convenience init() {
        self.init(frame: .zero)
    }

    override public init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
#if os(macOS)
        // `NSImageView.animates` is on by default, and a multi-frame `NSImage`
        // under it would play on AppKit's own timer beside the player.
        animates = false
#else
        // Smart Invert leaves the pictures alone, but only a view that says it
        // is showing one. Without this every frame is played inverted.
        accessibilityIgnoresInvertColors = true
#endif
    }

#if os(macOS)
    /// Draws the frames covering the view, which `NSImageView` cannot be asked
    /// to do. What hangs over the edge is taken care of by the default clipping.
    override public func draw(_ dirtyRect: NSRect) {
        guard isAspectFillEnabled, let image, image.size.width > 0, image.size.height > 0 else {
            return super.draw(dirtyRect)
        }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(
            x: bounds.midX - drawn.width / 2,
            y: bounds.midY - drawn.height / 2,
            width: drawn.width,
            height: drawn.height
        ))
    }
#endif

    // MARK: Displaying Images

    /// The image on screen: the frame the animation is showing while it plays,
    /// and whatever you set otherwise.
    ///
    /// Setting it stops the animation and forgets it: an animation left
    /// playing would paint over the new image on its next frame. Set
    /// ``animatedImage`` to play a new one, or ``isPlaybackEnabled`` to hold
    /// the one that is playing still.
    override public var image: PlatformImage? {
        get { super.image }
        set {
            animatedImage = nil
            super.image = newValue
        }
    }

    /// Puts an image on screen without stopping the animation: a frame the
    /// player produced, or the still that holds its place until the first one
    /// is decoded.
    func setImageKeepingAnimation(_ image: PlatformImage?) {
        super.image = image
    }

    /// Displays the image, playing it if the pipeline parsed an animation out
    /// of it.
    ///
    /// This is what ``ImageDisplaying/nuke_display(_:)`` reaches for a view of
    /// this type, and so the entry point the
    /// ``loadImage(with:options:into:completion:)-(URL?,_,_,_)`` extensions
    /// use. The still the decoder produced only goes on screen while there is
    /// no decoded frame to cover it.
    func display(_ container: ImageContainer?) {
        let poster = container?.image
        // Passed in rather than read back from the view: `self.image` is still
        // whatever the view was showing before this call.
        setAnimatedImage(container?.animation, scale: scale(of: poster))
        // Only while there is no frame to cover, so that an animation already
        // on screen doesn't flash its poster.
        if player?.image == nil {
            setImageKeepingAnimation(poster)
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

    // MARK: Layout

    // A view given an animation before it is laid out – a cell, and every
    // SwiftUI view – can't know what size to decode the frames for. It settles
    // that at the first layout with a size, and only for an animation that is
    // actually bigger than the view: the rebuild costs a decode.

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
        guard let source = sourcePendingDownsampling else { return }
        guard let maxPixelSize = automaticMaxPixelSize(for: source) else {
            // Laid out and still nothing to derive a size from: the view has
            // none, or its content mode draws the frames as they are. Full
            // size is what the frames will be decoded at, so stop waiting.
            player?.isDecodingEnabled = true
            return
        }
        sourcePendingDownsampling = nil
        guard maxPixelSize < max(source.size.width, source.size.height) else {
            player?.isDecodingEnabled = true // Already small enough as it is
            return
        }
        setPlayer(for: source, scale: player?.options.scale, maxPixelSize: maxPixelSize)
    }

    /// The longest side, in pixels, the frames need for the view to draw them
    /// at the size the content mode asks for – or `nil` when the view has no
    /// size yet, is decoding at a size it was given, or draws the frames at
    /// their own size.
    ///
    /// Not simply the longest side of the view: a content mode that covers the
    /// view does it with the frames' *shorter* side, so a 400×100 animation
    /// covering a 100×100 view needs 400-pixel frames.
    private func automaticMaxPixelSize(for source: AnimatedImageSource) -> CGFloat? {
        guard wantsAutomaticDownsampling else { return nil }
        let size = source.size
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0,
              let coversTheView = drawnFramesCoverTheView else { return nil }
        // The rule `ImageProcessors.Resize` uses: covering takes the larger of
        // the two scales, fitting the smaller.
        let horizontal = bounds.width / size.width
        let vertical = bounds.height / size.height
        let scale = coversTheView ? max(horizontal, vertical) : min(horizontal, vertical)
        let maxPixelSize = max(size.width, size.height) * scale * backingScale
        return (maxPixelSize / Self.pixelSizeStep).rounded(.up) * Self.pixelSizeStep
    }

    /// The step the size the frames are decoded at is rounded up to, in pixels.
    ///
    /// Views that differ by a fraction of a point – a grid whose cell is the
    /// width divided by three – would otherwise each decode the animation at a
    /// size of their own and share nothing. Rounding up costs at most a few
    /// percent more pixels per frame.
    private static let pixelSizeStep: CGFloat = 32

    /// Whether the content mode covers the view with the frames rather than
    /// fitting them inside it, or `nil` when it draws them at their own size.
    private var drawnFramesCoverTheView: Bool? {
#if os(macOS)
        if isAspectFillEnabled { return true }
        switch imageScaling {
        case .scaleProportionallyDown, .scaleProportionallyUpOrDown: return false
        case .scaleAxesIndependently: return true // Stretched: each side on its own
        case .scaleNone: return nil
        @unknown default: return true
        }
#else
        switch contentMode {
        case .scaleAspectFit: return false
        case .scaleAspectFill, .scaleToFill, .redraw: return true
        default: return nil // `.center` and the corners draw the frames unscaled
        }
#endif
    }

    private var backingScale: CGFloat {
#if os(macOS)
        max(window?.backingScaleFactor ?? 2, 1)
#else
        max(contentScaleFactor, 1)
#endif
    }

    private var wantsAutomaticDownsampling: Bool {
        isAutomaticDownsamplingEnabled && playerOptions.maxPixelSize == nil
    }

    // MARK: Visibility

    // A hidden or transparent view is as invisible as one outside a window,
    // and none of the three is worth a timer, a decode, or the frames the
    // buffer is holding. Hiding a cell's image view is how a list shows a
    // placeholder, so this is a state animations do sit in.

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

    override public var isHidden: Bool {
        didSet {
            guard isHidden != oldValue else { return }
            updatePlaybackState()
        }
    }

    // An animated fade sets the opacity to its final value the moment it
    // starts, so an animation being faded out stops on the first frame of the
    // fade. That is the cheaper mistake: the alternative is a decoder running
    // behind every view an app has faded away.

#if os(macOS)
    override public var alphaValue: CGFloat {
        didSet {
            guard (alphaValue > 0) != (oldValue > 0) else { return }
            updatePlaybackState()
        }
    }
#else
    override public var alpha: CGFloat {
        didSet {
            guard (alpha > 0) != (oldValue > 0) else { return }
            updatePlaybackState()
        }
    }
#endif

    /// Whether the view is somewhere its frames can be seen.
    ///
    /// Being in a window is as far as this goes: nothing tells a view that it
    /// is scrolled out of the visible area or covered, and a list takes its
    /// cells out of the window anyway.
    private var isVisible: Bool {
        guard window != nil, !isHidden else { return false }
#if os(macOS)
        return alphaValue > 0
#else
        return alpha > 0
#endif
    }

    // MARK: Private

    private func setAnimatedImage(_ source: AnimatedImageSource?, scale: CGFloat?) {
        guard _animatedImage !== source else { return }
        _animatedImage = source
        let maxPixelSize = source.flatMap(automaticMaxPixelSize(for:))
        setPlayer(for: source, scale: scale, maxPixelSize: maxPixelSize)
        // Set after the player, whose `didSet` clears it.
        sourcePendingDownsampling = maxPixelSize == nil && wantsAutomaticDownsampling ? source : nil
        // A view with no size of its own has nothing to decode for yet, and
        // the player it was given is the one the first layout replaces.
        // Decoding now would produce a full-size frame for a player that is
        // thrown away before it ever shows one.
        if sourcePendingDownsampling != nil, bounds.width == 0 || bounds.height == 0 {
            player?.isDecodingEnabled = false
#if os(macOS)
            needsLayout = true
#else
            setNeedsLayout()
#endif
        }
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
        let isOnScreen = isVisible || !isPlaybackPausedWhenOffscreen
        if isPlaybackEnabled && isOnScreen {
            player.play()
        } else {
            player.pause()
            if !isOnScreen {
                // Nobody is watching, so the window of decoded frames is a
                // budget spent on frames nobody will see. A player paused in
                // place keeps them: resuming shouldn't stall.
                player.keepsFullBuffer = false
            }
        }
    }
}

#endif

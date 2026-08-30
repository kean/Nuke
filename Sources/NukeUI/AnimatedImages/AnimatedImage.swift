// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import SwiftUI

/// A SwiftUI view that plays an animated image.
///
/// ``LazyImage`` displays animated images with it automatically, so you only
/// need it when you write your own content closure:
///
/// ```swift
/// LazyImage(url: url) { state in
///     if let animatedImage = state.animatedImage {
///         AnimatedImage(animatedImage)
///     } else if let image = state.image {
///         image.resizable().scaledToFit()
///     }
/// }
/// ```
///
/// The view sizes itself the way `Image` does: at the natural size of the
/// animation until you call ``resizable(contentMode:)``, after which it takes
/// the size it is offered and the usual layout modifiers apply.
///
/// ```swift
/// AnimatedImage(source).resizable().scaledToFit()
/// ```
///
/// Playback stops while the view is off screen and picks up where it left off
/// when it comes back, and it never starts on its own while Accessibility ›
/// Motion › Auto-Play Animated Images is off – the view shows the first frame
/// as a still instead. To control it yourself – or to read the diagnostics –
/// create an ``AnimatedImagePlayer`` and use ``init(player:)``.
@MainActor
public struct AnimatedImage: View {
    private let source: AnimatedImageSource
    private let player: AnimatedImagePlayer?
    private var contentMode: ContentMode = .fit
    private var isResizable = false

    /// Plays the given animated image.
    public init(_ source: AnimatedImageSource) {
        self.source = source
        self.player = nil
    }

    /// Displays the frames of a player you own.
    ///
    /// The view drives playback the same way it does for a player of its own:
    /// it plays while the view is on screen and pauses when it isn't.
    public init(player: AnimatedImagePlayer) {
        self.source = player.source
        self.player = player
    }

    /// Plays the image if the pipeline recognized it as animated.
    ///
    /// - returns: `nil` for anything that isn't an animated image, which is the
    /// signal to display ``ImageContainer/image`` as a still.
    public init?(container: ImageContainer) {
        guard let source = AnimatedImageSource.cached(container: container) else {
            return nil
        }
        self.init(source)
    }

    /// Lets the animation be resized to the space it is given, the way
    /// `Image.resizable()` does.
    ///
    /// - parameter contentMode: How the frames fill the view once it has been
    /// sized. `.fit` by default, which lays out like
    /// `Image.resizable().scaledToFit()`: the view takes the size the frames
    /// occupy rather than the box they were offered, so a background or a clip
    /// shape wraps the animation. `.fill` covers the box and clips the rest.
    public consuming func resizable(contentMode: ContentMode = .fit) -> Self {
        var copy = self
        copy.isResizable = true
        copy.contentMode = contentMode
        return copy
    }

    public var body: some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            AutoPlayReader { renderer(isPlaybackEnabled: $0) }
        } else {
            renderer(isPlaybackEnabled: true)
        }
    }

    @ViewBuilder
    private func renderer(isPlaybackEnabled: Bool) -> some View {
#if os(watchOS)
        AnimatedImageRenderer(source: source, player: player, contentMode: contentMode, isResizable: isResizable, isPlaybackEnabled: isPlaybackEnabled)
#else
        AnimatedImageRepresentable(source: source, player: player, contentMode: contentMode, isResizable: isResizable, isPlaybackEnabled: isPlaybackEnabled)
#endif
    }
}

/// Hands its content Accessibility › Motion › Auto-Play Animated Images, the
/// system-wide answer to whether an animation may start on its own.
///
/// A view of its own because the environment value needs iOS 17 and the
/// deployment target is iOS 16: an `@Environment` property on ``AnimatedImage``
/// can't be declared behind an availability check, but a whole view can.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
private struct AutoPlayReader<Content: View>: View {
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages

    let content: (Bool) -> Content

    var body: some View {
        content(playAnimatedImages)
    }
}

/// The size an ``AnimatedImage`` reports for a proposal.
///
/// A function rather than a method on the view so that the layout can be
/// tested without a view hierarchy.
func animatedImageSize(
    for proposal: ProposedViewSize,
    source size: CGSize,
    isResizable: Bool,
    contentMode: ContentMode
) -> CGSize? {
    guard size.width > 0, size.height > 0 else { return nil }
    guard isResizable else {
        return size // Same as an `Image` without `resizable()`
    }
    switch (proposal.width, proposal.height) {
    case (nil, nil):
        return size
    case let (width?, nil):
        return CGSize(width: width, height: width * size.height / size.width)
    case let (nil, height?):
        return CGSize(width: height * size.width / size.height, height: height)
    case let (width?, height?):
        // `.fill` covers what it is offered and the view clips what hangs over
        // the edge, which is `scaledToFill()` followed by `clipped()`.
        guard contentMode == .fit else {
            return CGSize(width: width, height: height)
        }
        // `.fit` reports the size the frames actually occupy, the way
        // `Image.resizable().scaledToFit()` does, so that a background or a
        // clip shape wraps the animation and not the box around it.
        let scale = min(width / size.width, height / size.height)
        guard scale.isFinite else { return size }
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

#if !os(watchOS)

#if os(macOS)
private typealias _PlatformViewRepresentable = NSViewRepresentable
#else
private typealias _PlatformViewRepresentable = UIViewRepresentable
#endif

/// Wraps ``AnimatedImageView``, which updates the image it displays directly
/// instead of going through the SwiftUI update cycle 20 times a second.
private struct AnimatedImageRepresentable: _PlatformViewRepresentable {
    let source: AnimatedImageSource
    let player: AnimatedImagePlayer?
    let contentMode: ContentMode
    let isResizable: Bool
    let isPlaybackEnabled: Bool

    private func makeView() -> AnimatedImageView {
        let view = AnimatedImageView()
#if !os(macOS)
        view.clipsToBounds = true
        // Without this the intrinsic size of the first frame wins every layout
        // argument and the view refuses to shrink.
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
#endif
        update(view)
        return view
    }

    /// The content mode and the playback are applied here rather than in
    /// ``makeView()`` because SwiftUI reuses the view across updates: a value
    /// that comes from state would otherwise be whatever it was the first time
    /// around.
    private func update(_ view: AnimatedImageView) {
        // Before the animation, whose arrival is what starts playback.
        view.isPlaybackEnabled = isPlaybackEnabled
#if os(macOS)
        // `NSImageView` has no aspect-fill mode; the view draws that one itself.
        view.isAspectFillEnabled = contentMode == .fill
        view.imageScaling = .scaleProportionallyUpOrDown
#else
        view.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
#endif
        if let player {
            view.player = player
        } else {
            view.animatedImage = source
        }
    }

    /// Reports the size the animation wants, so that the view behaves like an
    /// `Image` rather than collapsing or filling everything it is offered.
    private func size(for proposal: ProposedViewSize) -> CGSize? {
        animatedImageSize(for: proposal, source: source.size, isResizable: isResizable, contentMode: contentMode)
    }

#if os(macOS)
    func makeNSView(context: Context) -> AnimatedImageView { makeView() }
    func updateNSView(_ view: AnimatedImageView, context: Context) { update(view) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AnimatedImageView, context: Context) -> CGSize? {
        size(for: proposal)
    }
#else
    func makeUIView(context: Context) -> AnimatedImageView { makeView() }
    func updateUIView(_ view: AnimatedImageView, context: Context) { update(view) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AnimatedImageView, context: Context) -> CGSize? {
        size(for: proposal)
    }
#endif
}

#else

/// The watchOS renderer. There is no `UIViewRepresentable` there, so the frames
/// go through SwiftUI state – which is affordable at the frame rates and image
/// sizes a watch deals with.
private struct AnimatedImageRenderer: View {
    let source: AnimatedImageSource
    let player: AnimatedImagePlayer?
    let contentMode: ContentMode
    let isResizable: Bool
    let isPlaybackEnabled: Bool

    @StateObject private var model = AnimatedImageModel()

    var body: some View {
        content
            .onAppear { install() }
            .onDisappear {
                model.player?.pause()
                model.player?.keepsFullBuffer = false
            }
            // The view is reused when the image behind it changes – a new URL
            // loaded into the same `LazyImage`, say – and without this it would
            // keep playing the animation it was given first.
            .onChange(of: identity) { _ in install() }
            .onChange(of: isPlaybackEnabled) { isEnabled in
                if isEnabled { model.player?.play() } else { model.player?.pause() }
            }
    }

    private func install() {
        model.setPlayer(player ?? AnimatedImagePlayer(source: source))
        if isPlaybackEnabled {
            model.player?.play()
        }
    }

    /// What the renderer is playing, as something `onChange` can compare.
    private var identity: ObjectIdentifier {
        if let player {
            ObjectIdentifier(player)
        } else {
            ObjectIdentifier(source)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = model.image {
            if isResizable {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Image(uiImage: image)
            }
        } else if isResizable {
            Color.clear.aspectRatio(aspectRatio, contentMode: contentMode)
        } else {
            Color.clear.frame(width: source.size.width, height: source.size.height)
        }
    }

    private var aspectRatio: CGFloat? {
        guard source.size.width > 0, source.size.height > 0 else { return nil }
        return source.size.width / source.size.height
    }
}

@MainActor
private final class AnimatedImageModel: ObservableObject {
    @Published private(set) var image: PlatformImage?
    private(set) var player: AnimatedImagePlayer?

    func setPlayer(_ player: AnimatedImagePlayer) {
        guard self.player !== player else { return }
        self.player?.pause()
        self.player?.onFrame = nil
        self.player = player
        image = player.image
        player.onFrame = { [weak self] in self?.image = $0 }
    }
}

#endif

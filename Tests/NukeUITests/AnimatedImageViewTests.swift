// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageViewTests {
    let view = AnimatedImageView()

    /// Displays the image the way the pipeline does: in a container carrying
    /// the animation it parsed, rather than data for the view to find one in.
    private func display(_ data: Data?, image: PlatformImage? = Test.image) {
        guard let image else { return view.nuke_display(nil) }
        var container = ImageContainer(image: image, data: data)
        container.animation = data.flatMap(AnimatedImageSource.init(data:))
        view.nuke_display(container)
    }

    /// Asks the view to cover itself with the frames, which only UIKit has a
    /// content mode for: on AppKit every `imageScaling` fits.
    private func fillTheView() {
#if os(macOS)
        view.imageScaling = .scaleAxesIndependently
#else
        view.contentMode = .scaleAspectFill
#endif
    }

    /// Fades the view, which is `alpha` on UIKit and `alphaValue` on AppKit.
    private func setOpacity(_ opacity: CGFloat) {
#if os(macOS)
        view.alphaValue = opacity
#else
        view.alpha = opacity
#endif
    }

    /// A container the way the pipeline builds one for an animated image: the
    /// still, the data, and the animation parsed out of it.
    private func makeContainer(poster: PlatformImage, data: Data, animation: AnimatedImageSource) -> ImageContainer {
        var container = ImageContainer(image: poster, data: data)
        container.animation = animation
        return container
    }

    /// The pixels per point the view derives its sizes with: a view outside a
    /// window on AppKit assumes a Retina display.
    private var backingScale: CGFloat {
#if os(macOS)
        2
#else
        view.contentScaleFactor
#endif
    }

    /// Rounds a size in pixels up to the step the view decodes at.
    private func roundedUp(_ pixels: CGFloat) -> CGFloat {
        (pixels / 32).rounded(.up) * 32
    }

    /// Gives the view a size and runs a layout pass over it.
    private func layOut(_ size: CGSize) {
        view.frame = CGRect(origin: .zero, size: size)
#if os(macOS)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
#else
        view.setNeedsLayout()
        view.layoutIfNeeded()
#endif
    }

    // MARK: Displaying

    @Test func playsAnimatedData() async throws {
        layOut(CGSize(width: 100, height: 100))

        display(Test.animatedGIF())

        let player = try #require(view.player)
        #expect(player.source.frameCount == 4)
        await player.waitUntilFull()
        #expect(view.image != nil)
    }

    @Test func showsStillImageForNonAnimatedData() async {
        display(nil)

        #expect(view.player == nil)
        #expect(view.animatedImage == nil)
        #expect(view.image != nil)
    }

    @Test func showsStillImageForSingleFrameGIF() async {
        // Every GIF arrives with its data attached, so a still one has to be
        // recognized here rather than turned into a one-frame animation.
        display(Test.animatedGIF(frameCount: 1))

        #expect(view.player == nil)
        #expect(view.image != nil)
    }

    @Test func showsThePosterFrameBeforeTheFirstFrameIsDecoded() async {
        let poster = Test.image

        display(Test.animatedGIF(), image: poster)

        // The still the decoder produced is on screen right away; the player
        // replaces it when it has a frame of its own.
        #expect(view.image === poster)
    }

    @Test func replacesThePreviousAnimation() async throws {
        layOut(CGSize(width: 100, height: 100))
        display(Test.animatedGIF(frameCount: 4))
        let first = try #require(view.player)

        display(Test.animatedGIF(frameCount: 6))

        let second = try #require(view.player)
        #expect(first !== second)
        #expect(second.source.frameCount == 6)
        #expect(first.isPlaying == false)
    }

    @Test func showsTheStillOfAnImageThatIsNotAnimated() throws {
        // GIVEN an animation on screen
        layOut(CGSize(width: 100, height: 100))
        display(Test.animatedGIF(frameCount: 4))
        let first = try #require(view.player)

        // WHEN a still arrives
        let poster = Test.image
        display(nil, image: poster)

        // THEN the animation that belongs to the image being replaced is gone
        // and the new image's own still holds the place.
        #expect(view.image === poster)
        #expect(view.player == nil)
        #expect(first.isPlaying == false)
    }

    @Test func keepsThePlayerWhenTheSameSourceIsSetAgain() throws {
        layOut(CGSize(width: 100, height: 100))
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        view.animatedImage = source
        let player = try #require(view.player)

        view.animatedImage = source

        #expect(view.player === player)
    }

    @Test func prepareForReuseStopsEverything() async throws {
        layOut(CGSize(width: 100, height: 100))
        display(Test.animatedGIF())
        let player = try #require(view.player)

        view.prepareForReuse()

        #expect(view.player == nil)
        #expect(view.animatedImage == nil)
        #expect(view.image == nil)
        #expect(player.isPlaying == false)
    }

#if canImport(UIKit)
    @Test func usesTheScaleOfTheImageBeingDisplayed() async throws {
        layOut(CGSize(width: 100, height: 100))
        let image = UIImage(cgImage: Test.image.cgImage!, scale: 2, orientation: .up)

        display(Test.animatedGIF(), image: image)

        let player = try #require(view.player)
        #expect(player.options.scale == 2)
    }

    @Test func doesNotInheritTheScaleOfThePreviousImage() async throws {
        layOut(CGSize(width: 100, height: 100))
        let scaled = UIImage(cgImage: Test.image.cgImage!, scale: 2, orientation: .up)
        display(Test.animatedGIF(frameCount: 4), image: scaled)

        display(Test.animatedGIF(frameCount: 6))

        let player = try #require(view.player)
        #expect(player.options.scale == 1)
    }
#endif

    @Test func settingAnImageStopsTheAnimation() async {
        let host = TestWindow(view: view)
        display(Test.animatedGIF())
        #expect(view.isPlaying)
        let placeholder = Test.image

        view.image = placeholder

        // The animation would paint over the placeholder on its next frame.
        #expect(view.image === placeholder)
        #expect(view.isPlaying == false)
        #expect(view.player == nil)
        #expect(view.animatedImage == nil)
        host.close()
    }


    @Test func doesNotFlashThePosterWhenTheSameAnimationArrivesAgain() async throws {
        // A cell reloaded from the memory cache hands the view the animation
        // it is already playing, along with the still decoded beside it. The
        // still is the first frame, and the animation is somewhere else.
        layOut(CGSize(width: 100, height: 100))
        let data = Test.animatedGIF()
        let source = try #require(AnimatedImageSource(data: data))
        view.nuke_display(makeContainer(poster: Test.image, data: data, animation: source))
        let player = try #require(view.player)
        await player.waitUntilFull()
        let frame = try #require(player.image)
        #expect(view.image === frame)

        view.nuke_display(makeContainer(poster: Test.image, data: data, animation: source))

        #expect(view.player === player)
        #expect(view.image === frame)
    }

    @Test func clearsEverythingWhenItIsHandedNothing() async throws {
        layOut(CGSize(width: 100, height: 100))
        display(Test.animatedGIF())
        let player = try #require(view.player)
        await player.waitUntilFull()

        view.nuke_display(nil)

        #expect(view.player == nil)
        #expect(view.animatedImage == nil)
        #expect(view.image == nil)
    }

    @Test func settingAnImageForgetsAnAnimationWaitingForASize() {
        view.animatedImage = Test.animatedGIFSource(size: CGSize(width: 200, height: 200))
        #expect(view.animatedImage != nil)
        let still = Test.image

        view.image = still
        layOut(CGSize(width: 20, height: 20))

        // The first layout would otherwise build a player for the animation
        // and paint it over the still.
        #expect(view.player == nil)
        #expect(view.animatedImage == nil)
        #expect(view.image === still)
    }

    @Test func prepareForReuseForgetsAnAnimationWaitingForASize() {
        display(Test.animatedGIF(size: CGSize(width: 200, height: 200)))
        #expect(view.animatedImage != nil)

        view.prepareForReuse()
        layOut(CGSize(width: 20, height: 20))

        #expect(view.player == nil)
        #expect(view.animatedImage == nil)
        #expect(view.image == nil)
    }

    @Test func newOptionsApplyFromTheNextAnimation() throws {
        layOut(CGSize(width: 100, height: 100))
        view.animatedImage = Test.animatedGIFSource()
        let first = try #require(view.player)

        view.playerOptions.playbackRate = 2

        #expect(view.player === first)
        #expect(first.options.playbackRate == 1)

        view.animatedImage = Test.animatedGIFSource()

        #expect(view.player !== first)
        #expect(view.player?.options.playbackRate == 2)
    }

    @Test func aFrameOnScreenDoesNotStopTheAnimation() async throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        let player = AnimatedImagePlayer(source: source)
        await player.waitUntilFull()
        view.player = player

        player.seek(toFrame: 1)

        #expect(view.image != nil)
        #expect(view.player === player)
        #expect(view.animatedImage === source)
    }

    // MARK: Downsampling

    @Test func decodesTheFramesNoLargerThanTheView() async throws {
        layOut(CGSize(width: 20, height: 20))

        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))

        let player = try #require(view.player)
        let maxPixelSize = try #require(player.options.maxPixelSize)
        #expect(maxPixelSize < 400)
        await player.waitUntilFull()
        let frame = try #require(player.image?.cgImage)
        #expect(max(frame.width, frame.height) <= Int(maxPixelSize))
    }

    @Test func decodesFramesLargeEnoughToCoverTheView() async throws {
        // Covering the view uses the frames' shorter side, so a wide animation
        // in a square view needs more pixels than the view has points: decoding
        // it for the view's longest side hands the view a frame to scale up.
        fillTheView()
        layOut(CGSize(width: 100, height: 100))

        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 100)))

        let player = try #require(view.player)
        await player.waitUntilFull()
        let frame = try #require(player.image?.cgImage)
        // The height is what covers the view, and it is already only just big
        // enough, so the frames are decoded as they are.
        #expect(frame.width == 400)
        #expect(frame.height == 100)
    }

    @Test func doesNotDeriveASizeForFramesItDrawsUnscaled() async throws {
        // There is no view size to decode for: the frames are drawn at their
        // own size and the view shows whatever part of them fits.
#if os(macOS)
        view.imageScaling = .scaleNone
#else
        view.contentMode = .center
#endif
        layOut(CGSize(width: 20, height: 20))

        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))

        #expect(try #require(view.player).options.maxPixelSize == nil)
    }

    @Test func decodesNothingUntilItKnowsWhatSizeToDecodeFor() async throws {
        // The view is given the animation before it has a size, which is every
        // SwiftUI view – they are made at zero size – and every cell.
        display(Test.animatedGIF(size: CGSize(width: 200, height: 200)))

        // There is no player yet, and so nothing decoded: the frames would be
        // full size, and both they and the player that produced them would be
        // thrown away at the first layout. A frame of a large animation is a
        // decode and a bitmap the size of the whole canvas, per cell.
        #expect(view.player == nil)
        #expect(view.animatedImage != nil)

        layOut(CGSize(width: 20, height: 20))

        let player = try #require(view.player)
        await player.waitUntilFull()
        #expect(player.diagnostics.decodedFrameCount > 0)
    }

    @Test func decodesOnceALayoutSettlesThatThereIsNoSizeToDeriveFrom() async throws {
        // A view laid out with no size of its own is not going to get a better
        // answer, so the frames are decoded as they are rather than never.
        display(Test.animatedGIF(size: CGSize(width: 200, height: 200)))

        layOut(.zero)

        let player = try #require(view.player)
        #expect(player.options.maxPixelSize == nil)
        await player.waitUntilFull()
        #expect(player.diagnostics.decodedFrameCount > 0)
    }

    @Test func derivesTheSizeAtTheFirstLayoutWhenItHasNoneYet() async {
        // A cell hasn't been laid out when the image arrives, and a SwiftUI
        // view has no size at all when it is made.
        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))
        #expect(view.player == nil)

        layOut(CGSize(width: 20, height: 20))

        #expect(view.player?.options.maxPixelSize != nil)
    }

    @Test func doesNotRebuildThePlayerForAnAnimationThatAlreadyFits() async throws {
        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 8, height: 8)))
        layOut(CGSize(width: 200, height: 200))
        let player = try #require(view.player)

        layOut(CGSize(width: 300, height: 300))

        // Decoding it again would buy nothing: the frames are already smaller
        // than the view.
        #expect(view.player === player)
        #expect(player.options.maxPixelSize == nil)
    }

    @Test func keepsItsFramesWhenTheViewShrinks() async throws {
        // Handed the animation before its first layout, the way every cell and
        // every SwiftUI view is, and then laid out larger than the animation.
        display(Test.animatedGIF(frameCount: 4, size: CGSize(width: 100, height: 100)))
        layOut(CGSize(width: 200, height: 200))
        let player = try #require(view.player)
        #expect(player.options.maxPixelSize == nil)

        layOut(CGSize(width: 10, height: 10))

        // Smaller frames would save little and cost a decode: the animation
        // was settled at the first layout, not left waiting for a size.
        #expect(view.player === player)
        #expect(view.player?.store === player.store)
    }

    @Test func decodesTheFramesAgainWhenTheViewGrows() async throws {
        layOut(CGSize(width: 20, height: 20))
        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))
        let player = try #require(view.player)
        let small = try #require(player.options.maxPixelSize)

        layOut(CGSize(width: 60, height: 60))

        // A rotation, a split view, or a window dragged wider: the frames the
        // view settled on would be scaled up for the rest of its life.
        let grown = try #require(view.player)
        #expect(grown !== player)
        #expect(try #require(grown.options.maxPixelSize) > small)
    }

    @Test func keepsItsFramesWhenTheViewBarelyChangesSize() async throws {
        layOut(CGSize(width: 20, height: 20))
        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))
        let player = try #require(view.player)

        layOut(CGSize(width: 21, height: 21))

        // A point of growth is not worth a decode, and a resize that is dragged
        // rather than jumped arrives a point at a time.
        #expect(view.player === player)
    }

    @Test func carriesThePlayheadOverWhenItDecodesTheFramesAgain() async throws {
        layOut(CGSize(width: 20, height: 20))
        display(Test.animatedGIF(frameCount: 4, size: CGSize(width: 400, height: 400)))
        let player = try #require(view.player)
        player.seek(toFrame: 2)

        layOut(CGSize(width: 60, height: 60))

        let grown = try #require(view.player)
        #expect(grown !== player)
        #expect(grown.currentFrameIndex == 2)
    }

    @Test func leavesAPlayerItWasGivenAtTheSizeItWasBuiltFor() async throws {
        layOut(CGSize(width: 20, height: 20))
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400))))
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 32
        let player = AnimatedImagePlayer(source: source, options: options)
        view.player = player

        layOut(CGSize(width: 200, height: 200))

        // The size belongs to whoever built the player.
        #expect(view.player === player)
    }

    @Test func neverScalesTheFramesUp() async throws {
        layOut(CGSize(width: 200, height: 200))

        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 8, height: 8)))

        let player = try #require(view.player)
        await player.waitUntilFull()
        let frame = try #require(player.image?.cgImage)
        #expect(frame.width == 8)
    }

    @Test func downsamplingCanBeTurnedOff() async throws {
        view.isAutomaticDownsamplingEnabled = false
        layOut(CGSize(width: 20, height: 20))

        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))

        #expect(try #require(view.player).options.maxPixelSize == nil)
    }

    @Test func decodesForTheScaleItsContentModeDrawsTheFramesAt() throws {
        // A 400×400 animation in a 20×10 view. Fitting it inside takes the
        // smaller of the two scales, covering the view the larger, and the
        // modes that draw the frames unscaled have no size to derive. Every
        // size is rounded up to a step of 32 pixels.
        let source = Test.animatedGIFSource(frameCount: 2, size: CGSize(width: 400, height: 400))
        let fit = roundedUp(10 * backingScale)
        let cover = roundedUp(20 * backingScale)
#if os(macOS)
        let modes: [(NSImageScaling, CGFloat?)] = [
            (.scaleProportionallyDown, fit),
            (.scaleProportionallyUpOrDown, fit),
            (.scaleAxesIndependently, cover),
            (.scaleNone, nil)
        ]
#else
        let modes: [(UIView.ContentMode, CGFloat?)] = [
            (.scaleAspectFit, fit),
            (.scaleAspectFill, cover),
            (.scaleToFill, cover),
            (.redraw, cover),
            (.center, nil),
            (.topLeft, nil),
            (.bottom, nil)
        ]
#endif
        for (mode, expected) in modes {
            let view = AnimatedImageView(frame: CGRect(x: 0, y: 0, width: 20, height: 10))
#if os(macOS)
            view.imageScaling = mode
#else
            view.contentMode = mode
#endif
            view.animatedImage = source

            let player = try #require(view.player)
            #expect(player.options.maxPixelSize == expected, "\(mode.rawValue)")
        }
    }

    @Test func viewsAFractionOfAPointApartDecodeOneSetOfFrames() throws {
        // A grid whose cell is the width divided by three: without the step,
        // each cell would decode the animation at a size of its own.
        let source = Test.animatedGIFSource(frameCount: 2, size: CGSize(width: 400, height: 400))
        layOut(CGSize(width: 20, height: 20))
        view.animatedImage = source
        let other = AnimatedImageView(frame: CGRect(x: 0, y: 0, width: 20.4, height: 20.4))

        other.animatedImage = source

        let size = try #require(view.player?.options.maxPixelSize)
        #expect(size.truncatingRemainder(dividingBy: 32) == 0)
        #expect(other.player?.options.maxPixelSize == size)
        #expect(other.player?.store === view.player?.store)
    }

    @Test func picksASizeOnceTheContentModeStartsScalingTheFrames() throws {
        // Drawn unscaled, there is no size to decode for, so the frames are
        // decoded whole; the view keeps waiting for one in case the content
        // mode changes, and carries on from the frame it was showing when it
        // does.
#if os(macOS)
        view.imageScaling = .scaleNone
#else
        view.contentMode = .center
#endif
        layOut(CGSize(width: 20, height: 20))
        display(Test.animatedGIF(frameCount: 4, size: CGSize(width: 400, height: 400)))
        let unscaled = try #require(view.player)
        #expect(unscaled.options.maxPixelSize == nil)
        unscaled.seek(toFrame: 2)

#if os(macOS)
        view.imageScaling = .scaleProportionallyUpOrDown
#else
        view.contentMode = .scaleAspectFit
#endif
        layOut(CGSize(width: 20, height: 20))

        let scaled = try #require(view.player)
        #expect(scaled !== unscaled)
        #expect(try #require(scaled.options.maxPixelSize) < 400)
        #expect(scaled.currentFrameIndex == 2)
    }

    @Test func aPlayerItIsGivenWinsOverAnAnimationWaitingForASize() throws {
        view.animatedImage = Test.animatedGIFSource(size: CGSize(width: 200, height: 200))
        // Larger than the view, so that a layout still waiting would derive a
        // size for it and build a downsampled player in place of this one.
        let source = Test.animatedGIFSource(size: CGSize(width: 400, height: 400))
        let player = AnimatedImagePlayer(source: source)

        view.player = player
        layOut(CGSize(width: 20, height: 20))

        // The layout that was going to build a player for the animation
        // waiting on it finds one it was handed instead.
        #expect(view.player === player)
        #expect(view.animatedImage === source)
    }

    @Test func aSizeOfYourOwnWins() async throws {
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 64
        view.playerOptions = options
        layOut(CGSize(width: 20, height: 20))

        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))

        #expect(try #require(view.player).options.maxPixelSize == 64)
    }

    // MARK: Playback and Visibility

    @Test func doesNotPlayOutsideAWindow() {
        view.animatedImage = Test.animatedGIFSource()

        #expect(view.isPlaying == false)
    }

    @Test func playsOnceItIsInAWindow() {
        let host = TestWindow(view: view)
        view.animatedImage = Test.animatedGIFSource()

        #expect(view.isPlaying)
        host.close()
    }

    @Test func pausesWhenItLeavesTheWindow() {
        let host = TestWindow(view: view)
        view.animatedImage = Test.animatedGIFSource()
        #expect(view.isPlaying)

        view.removeFromSuperview()

        #expect(view.isPlaying == false)
        host.close()
    }

    @Test func releasesTheBufferWhenItLeavesTheWindow() async throws {
        let host = TestWindow(view: view)
        view.animatedImage = Test.animatedGIFSource(frameCount: 8)
        let player = try #require(view.player)
        await player.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 8)

        view.removeFromSuperview()

        // Off screen, the animation is worth two frames, not a whole budget.
        #expect(player.diagnostics.bufferedFrameCount == AnimatedImagePlayer.idleFrameCount)
        host.close()
    }

    @Test func keepsTheBufferWhenPlaybackIsPausedInPlace() async throws {
        let host = TestWindow(view: view)
        view.animatedImage = Test.animatedGIFSource(frameCount: 8)
        let player = try #require(view.player)
        await player.waitUntilFull()

        view.isPlaybackEnabled = false

        // Still on screen: resuming should not have to decode it all again.
        #expect(player.isPlaying == false)
        #expect(player.diagnostics.bufferedFrameCount == 8)
        host.close()
    }

    @Test func pausesWhileHidden() {
        let host = TestWindow(view: view)
        view.animatedImage = Test.animatedGIFSource()
        #expect(view.isPlaying)

        view.isHidden = true
        #expect(view.isPlaying == false)

        view.isHidden = false

        #expect(view.isPlaying)
        host.close()
    }

    @Test func pausesWhileFullyTransparent() {
        let host = TestWindow(view: view)
        view.animatedImage = Test.animatedGIFSource()
        #expect(view.isPlaying)

        setOpacity(0)
        #expect(view.isPlaying == false)

        setOpacity(1)

        #expect(view.isPlaying)
        host.close()
    }

    @Test func keepsPlayingWhileBarelyVisible() {
        let host = TestWindow(view: view)
        view.animatedImage = Test.animatedGIFSource()

        setOpacity(0.01)

        // Faint is not invisible, and the user can see it move.
        #expect(view.isPlaying)
        host.close()
    }

    @Test func doesNotPlayAnAnimationItIsGivenWhileHidden() {
        let host = TestWindow(view: view)
        view.isHidden = true

        view.animatedImage = Test.animatedGIFSource()

        #expect(view.isPlaying == false)
        host.close()
    }

    @Test func releasesTheBufferWhenItIsHidden() async throws {
        let host = TestWindow(view: view)
        view.animatedImage = Test.animatedGIFSource(frameCount: 8)
        let player = try #require(view.player)
        await player.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 8)

        view.isHidden = true

        #expect(player.diagnostics.bufferedFrameCount == AnimatedImagePlayer.idleFrameCount)
        host.close()
    }

    @Test func playsOutsideAWindowWhenAsked() {
        layOut(CGSize(width: 100, height: 100))
        view.isPlaybackPausedWhenOffscreen = false
        view.animatedImage = Test.animatedGIFSource()

        #expect(view.isPlaying)
    }

    @Test func playsWhileHiddenWhenAsked() {
        let host = TestWindow(view: view)
        view.isPlaybackPausedWhenOffscreen = false
        view.isHidden = true

        view.animatedImage = Test.animatedGIFSource()

        #expect(view.isPlaying)
        host.close()
    }

    @Test func playbackCanBeDisabled() {
        let host = TestWindow(view: view)
        view.isPlaybackEnabled = false
        view.animatedImage = Test.animatedGIFSource()
        #expect(view.isPlaying == false)

        view.isPlaybackEnabled = true

        #expect(view.isPlaying)
        host.close()
    }

    @Test func anAnimationHeldStillShowsItsFirstFrameWithoutFillingTheBuffer() async throws {
        // A table full of animations waiting for the user to ask for them:
        // each one is a still, not a window of decoded frames.
        let host = TestWindow(view: view)
        view.isPlaybackEnabled = false
        view.animatedImage = Test.animatedGIFSource(frameCount: 8)
        let player = try #require(view.player)

        await player.waitUntilFull()

        #expect(view.image != nil)
        #expect(view.image === player.image)
        #expect(player.currentFrameIndex == 0)
        #expect(player.diagnostics.bufferedFrameCount <= AnimatedImagePlayer.idleFrameCount)
        host.close()
    }

    @Test func anAnimationHeldStillHoldsTheFrameAfterTheFirstAndNothingMore() async throws {
        // The floor every player keeps: the frame on screen and the one after
        // it, so that playback can start without waiting on a decode.
        let host = TestWindow(view: view)
        view.isPlaybackEnabled = false
        view.animatedImage = Test.animatedGIFSource(frameCount: 8)
        let player = try #require(view.player)

        await player.waitUntilFull()

        #expect(player.isFrameBuffered(0))
        #expect(player.isFrameBuffered(1))
        #expect(player.isFrameBuffered(2) == false)
        #expect(player.diagnostics.decodedFrameCount == AnimatedImagePlayer.idleFrameCount)
        host.close()
    }

    @Test func anAnimationHeldStillShowsTheFirstFrameAnotherPlayerDecoded() async {
        // A cell that comes back for an animation whose frames are still in
        // memory: nothing is left to decode, and no poster to fall back on.
        let host = TestWindow(view: view)
        let source = Test.animatedGIFSource(frameCount: 8)
        let other = AnimatedImagePlayer(source: source)
        await other.waitUntilFull()

        view.isPlaybackEnabled = false
        view.animatedImage = source

        #expect(view.image != nil)
        #expect(view.image === view.player?.image)
        host.close()
    }

    @Test func picksUpWhereItLeftOffWhenItComesBackToTheWindow() async throws {
        // A cell that scrolls off screen and back: the same player, on the
        // frame it stopped on, with its window of frames back.
        let host = TestWindow(view: view)
        view.animatedImage = Test.animatedGIFSource(frameCount: 8)
        let player = try #require(view.player)
        player.seek(toFrame: 5)
        let superview = try #require(view.superview)
        view.removeFromSuperview()
        #expect(view.isPlaying == false)
        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount)

        superview.addSubview(view)

        #expect(view.player === player)
        #expect(view.isPlaying)
        #expect(player.currentFrameIndex == 5)
        #expect(player.diagnostics.bufferCapacity == 8)
        host.close()
    }

    @Test func startsPlayingOutsideAWindowWhenToldTo() async throws {
        layOut(CGSize(width: 100, height: 100))
        view.animatedImage = Test.animatedGIFSource(frameCount: 8)
        let player = try #require(view.player)
        #expect(view.isPlaying == false)

        view.isPlaybackPausedWhenOffscreen = false
        #expect(view.isPlaying)
        #expect(player.diagnostics.bufferCapacity == 8)

        view.isPlaybackPausedWhenOffscreen = true

        #expect(view.isPlaying == false)
        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount)
    }

    // MARK: External Players

    @Test func adoptsAPlayerItIsGiven() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        let player = AnimatedImagePlayer(source: source)

        view.player = player

        #expect(view.animatedImage === source)
        #expect(view.player === player)
    }

    @Test func displaysTheFramesOfThePlayerItIsGiven() async throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        let player = AnimatedImagePlayer(source: source)
        await player.waitUntilFull()

        view.player = player

        // The frame the player already has is displayed immediately.
        #expect(view.image != nil)
    }

    @Test func leavesTheFrameHandlerOfThePlayerItIsGivenAlone() async throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        let player = AnimatedImagePlayer(source: source)
        var frames = 0
        player.onFrame = { _ in frames += 1 }

        view.player = player
        await player.waitUntilFull()

        // A player driving something of yours – a scrubber, a frame counter –
        // goes on driving it after a view is given it to display.
        #expect(frames > 0)
        #expect(view.image != nil)
    }

    @Test func keepsTheFrameHandlerOfAPlayerItHasLetGoOf() async throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        let player = AnimatedImagePlayer(source: source)
        var frames = 0
        player.onFrame = { _ in frames += 1 }
        view.player = player
        await player.waitUntilFull()

        view.player = nil
        let before = frames
        // Frame 1: the view left the player outside a window, so it is holding
        // the frame on screen and the one after it, and nothing further along.
        player.seek(toFrame: 1)

        #expect(frames > before)
    }

    @Test func stopsShowingTheFramesOfAPlayerItHasLetGoOf() async throws {
        let first = AnimatedImagePlayer(source: Test.animatedGIFSource())
        await first.waitUntilFull()
        view.player = first
        let second = AnimatedImagePlayer(source: Test.animatedGIFSource(frameCount: 6))
        await second.waitUntilFull()
        view.player = second
        let shown = try #require(view.image)
        #expect(shown === second.image)

        first.seek(toFrame: 1)

        // The first player moved on to a frame of its own, and it didn't
        // reach the view that is showing the second one.
        #expect(first.image != nil)
        #expect(view.image === shown)
        #expect(view.image !== first.image)
    }

    // MARK: Archiving

    @Test func aViewLoadedFromAnArchiveIsSetUpLikeOneMadeInCode() throws {
        // What a storyboard or a nib does: a plain image view with the
        // platform's defaults, decoded as this class.
        let plain = _PlatformImageView()
#if os(macOS)
        #expect(plain.animates)
#else
        #expect(plain.accessibilityIgnoresInvertColors == false)
#endif
        let data = try NSKeyedArchiver.archivedData(withRootObject: plain, requiringSecureCoding: false)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(AnimatedImageView.self, forClassName: NSStringFromClass(_PlatformImageView.self))

        let view = try #require(unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? AnimatedImageView)

#if os(macOS)
        #expect(view.animates == false)
#else
        #expect(view.accessibilityIgnoresInvertColors)
#endif
        let host = TestWindow(view: view)
        view.animatedImage = Test.animatedGIFSource()
        #expect(view.isPlaying)
        host.close()
    }

#if !os(macOS)
    // MARK: UIKit

    @Test func doesNotLetSmartInvertReverseTheFrames() {
        // Smart Invert leaves the pictures in an interface alone only where a
        // view says it is showing one, and every frame is a picture.
        #expect(view.accessibilityIgnoresInvertColors)
        #expect(AnimatedImageView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)).accessibilityIgnoresInvertColors)
    }
#endif

#if os(macOS)
    // MARK: AppKit

    @Test func doesNotLetAppKitPlayTheImage() {
        // `NSImageView.animates` is on by default and plays a multi-frame
        // `NSImage` on a timer of its own – beside the player, and under a view
        // that is meant to be holding a still.
        #expect(view.animates == false)
    }

    @Test func fitsTheFramesInsideTheViewByDefault() throws {
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        view.imageScaling = .scaleProportionallyUpOrDown

        view.image = wideImage()

        // Letterboxed: the image is a band across the middle and the corners
        // are the empty space above and below it.
        #expect(try corners(of: view) == [.empty, .empty, .empty, .empty])
    }

    private enum Swatch: Equatable {
        case empty, red, green, blue, white, other
    }

    /// The colors of the four corners of what the view draws.
    private func corners(of view: NSView) throws -> [Swatch] {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        return [(5.0, 5.0), (95.0, 5.0), (5.0, 95.0), (95.0, 95.0)].map { x, y in
            guard let color = rep.colorAt(x: Int(x * scale), y: Int(y * scale)) else { return .other }
            guard color.alphaComponent > 0.5 else { return .empty }
            let (r, g, b) = (color.redComponent, color.greenComponent, color.blueComponent)
            switch (r > 0.5, g > 0.5, b > 0.5) {
            case (true, false, false): return .red
            case (false, true, false): return .green
            case (false, false, true): return .blue
            case (true, true, true): return .white
            default: return .other
            }
        }
    }

    /// A 400×100 image in four vertical bands: red, green, blue, white.
    private func wideImage() -> NSImage {
        let (width, height) = (400, 100)
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let colors: [NSColor] = [.red, .green, .blue, .white]
        for (index, color) in colors.enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: index * 100, y: 0, width: 100, height: height))
        }
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
    }
#endif
}

/// Puts a view in a window, which is what makes it start animating.
@MainActor
private final class TestWindow {
#if os(macOS)
    private let window: NSWindow

    init(view: NSView) {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        view.frame = frame
        window.contentView?.addSubview(view)
        window.orderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }
#else
    private let window: UIWindow

    init(view: UIView) {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        window = UIWindow(frame: frame)
        view.frame = frame // A view in a window has a size, as the AppKit half does
        window.addSubview(view)
        window.isHidden = false
    }

    func close() {
        window.isHidden = true
    }
#endif
}

#endif

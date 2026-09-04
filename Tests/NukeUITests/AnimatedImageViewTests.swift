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

    @Test func settingAnImageStopsTheAnimation() async throws {
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

    @Test func derivesTheSizeAtTheFirstLayoutWhenItHasNoneYet() async throws {
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

    @Test func aSizeOfYourOwnWins() async throws {
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 64
        view.playerOptions = options
        layOut(CGSize(width: 20, height: 20))

        display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))

        #expect(try #require(view.player).options.maxPixelSize == 64)
    }

    // MARK: Playback and Visibility

    @Test func doesNotPlayOutsideAWindow() throws {
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))

        #expect(view.isPlaying == false)
    }

    @Test func playsOnceItIsInAWindow() throws {
        let host = TestWindow(view: view)
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))

        #expect(view.isPlaying)
        host.close()
    }

    @Test func pausesWhenItLeavesTheWindow() throws {
        let host = TestWindow(view: view)
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        #expect(view.isPlaying)

        view.removeFromSuperview()

        #expect(view.isPlaying == false)
        host.close()
    }

    @Test func releasesTheBufferWhenItLeavesTheWindow() async throws {
        let host = TestWindow(view: view)
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 8)))
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
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 8)))
        let player = try #require(view.player)
        await player.waitUntilFull()

        view.isPlaybackEnabled = false

        // Still on screen: resuming should not have to decode it all again.
        #expect(player.isPlaying == false)
        #expect(player.diagnostics.bufferedFrameCount == 8)
        host.close()
    }

    @Test func pausesWhileHidden() throws {
        let host = TestWindow(view: view)
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        #expect(view.isPlaying)

        view.isHidden = true
        #expect(view.isPlaying == false)

        view.isHidden = false

        #expect(view.isPlaying)
        host.close()
    }

    @Test func pausesWhileFullyTransparent() throws {
        let host = TestWindow(view: view)
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        #expect(view.isPlaying)

        setOpacity(0)
        #expect(view.isPlaying == false)

        setOpacity(1)

        #expect(view.isPlaying)
        host.close()
    }

    @Test func keepsPlayingWhileBarelyVisible() throws {
        let host = TestWindow(view: view)
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))

        setOpacity(0.01)

        // Faint is not invisible, and the user can see it move.
        #expect(view.isPlaying)
        host.close()
    }

    @Test func doesNotPlayAnAnimationItIsGivenWhileHidden() throws {
        let host = TestWindow(view: view)
        view.isHidden = true

        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))

        #expect(view.isPlaying == false)
        host.close()
    }

    @Test func releasesTheBufferWhenItIsHidden() async throws {
        let host = TestWindow(view: view)
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 8)))
        let player = try #require(view.player)
        await player.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 8)

        view.isHidden = true

        #expect(player.diagnostics.bufferedFrameCount == AnimatedImagePlayer.idleFrameCount)
        host.close()
    }

    @Test func playsOutsideAWindowWhenAsked() throws {
        layOut(CGSize(width: 100, height: 100))
        view.isPlaybackPausedWhenOffscreen = false
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))

        #expect(view.isPlaying)
    }

    @Test func playsWhileHiddenWhenAsked() throws {
        let host = TestWindow(view: view)
        view.isPlaybackPausedWhenOffscreen = false
        view.isHidden = true

        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))

        #expect(view.isPlaying)
        host.close()
    }

    @Test func playbackCanBeDisabled() throws {
        let host = TestWindow(view: view)
        view.isPlaybackEnabled = false
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        #expect(view.isPlaying == false)

        view.isPlaybackEnabled = true

        #expect(view.isPlaying)
        host.close()
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

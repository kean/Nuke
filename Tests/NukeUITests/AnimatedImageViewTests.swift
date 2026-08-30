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

    /// Displays the image and waits for the animation to be parsed, which the
    /// view does off the main thread the first time it sees one.
    private func display(_ data: Data?, image: PlatformImage? = Test.image) async {
        view.nuke_display(image: image, data: data)
        await view.pendingParse?.value
    }

    /// Asks the view to cover itself with the frames, which is a content mode
    /// on UIKit and a view of its own on AppKit.
    private func fillTheView() {
#if os(macOS)
        view.isAspectFillEnabled = true
#else
        view.contentMode = .scaleAspectFill
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
        await display(Test.animatedGIF())

        let player = try #require(view.player)
        #expect(player.source.frameCount == 4)
        await player.buffer.waitUntilFull()
        #expect(view.image != nil)
    }

    @Test func showsStillImageForNonAnimatedData() async {
        await display(nil)

        #expect(view.player == nil)
        #expect(view.animatedImage == nil)
        #expect(view.image != nil)
    }

    @Test func showsStillImageForSingleFrameGIF() async {
        // Every GIF arrives with its data attached, so a still one has to be
        // recognized here rather than turned into a one-frame animation.
        await display(Test.animatedGIF(frameCount: 1))

        #expect(view.player == nil)
        #expect(view.image != nil)
    }

    @Test func showsThePosterFrameBeforeTheFirstFrameIsDecoded() async {
        let poster = Test.image

        await display(Test.animatedGIF(), image: poster)

        // The still the decoder produced is on screen right away; the player
        // replaces it when it has a frame of its own.
        #expect(view.image === poster)
    }

    @Test func replacesThePreviousAnimation() async throws {
        await display(Test.animatedGIF(frameCount: 4))
        let first = try #require(view.player)

        await display(Test.animatedGIF(frameCount: 6))

        let second = try #require(view.player)
        #expect(first !== second)
        #expect(second.source.frameCount == 6)
        #expect(first.isPlaying == false)
    }

    @Test func keepsThePlayerWhenTheSameSourceIsSetAgain() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        view.animatedImage = source
        let player = try #require(view.player)

        view.animatedImage = source

        #expect(view.player === player)
    }

    @Test func prepareForReuseStopsEverything() async throws {
        await display(Test.animatedGIF())
        let player = try #require(view.player)

        view.prepareForReuse()

        #expect(view.player == nil)
        #expect(view.animatedImage == nil)
        #expect(view.image == nil)
        #expect(player.isPlaying == false)
    }

#if canImport(UIKit)
    @Test func usesTheScaleOfTheImageBeingDisplayed() async throws {
        let image = UIImage(cgImage: Test.image.cgImage!, scale: 2, orientation: .up)

        await display(Test.animatedGIF(), image: image)

        let player = try #require(view.player)
        #expect(player.options.scale == 2)
    }

    @Test func doesNotInheritTheScaleOfThePreviousImage() async throws {
        let scaled = UIImage(cgImage: Test.image.cgImage!, scale: 2, orientation: .up)
        await display(Test.animatedGIF(frameCount: 4), image: scaled)

        await display(Test.animatedGIF(frameCount: 6))

        let player = try #require(view.player)
        #expect(player.options.scale == 1)
    }
#endif

    // MARK: Downsampling

    @Test func decodesTheFramesNoLargerThanTheView() async throws {
        layOut(CGSize(width: 20, height: 20))

        await display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))

        let player = try #require(view.player)
        let maxPixelSize = try #require(player.options.maxPixelSize)
        #expect(maxPixelSize < 400)
        await player.buffer.waitUntilFull()
        let frame = try #require(player.image?.cgImage)
        #expect(max(frame.width, frame.height) <= Int(maxPixelSize))
    }

    @Test func decodesFramesLargeEnoughToCoverTheView() async throws {
        // Covering the view uses the frames' shorter side, so a wide animation
        // in a square view needs more pixels than the view has points: decoding
        // it for the view's longest side hands the view a frame to scale up.
        fillTheView()
        layOut(CGSize(width: 100, height: 100))

        await display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 100)))

        let player = try #require(view.player)
        await player.buffer.waitUntilFull()
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

        await display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))

        #expect(try #require(view.player).options.maxPixelSize == nil)
    }

    @Test func derivesTheSizeAtTheFirstLayoutWhenItHasNoneYet() async throws {
        // A cell hasn't been laid out when the image arrives, and a SwiftUI
        // view has no size at all when it is made.
        await display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))
        #expect(view.player?.options.maxPixelSize == nil)

        layOut(CGSize(width: 20, height: 20))

        #expect(view.player?.options.maxPixelSize != nil)
    }

    @Test func doesNotRebuildThePlayerForAnAnimationThatAlreadyFits() async throws {
        await display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 8, height: 8)))
        let player = try #require(view.player)

        layOut(CGSize(width: 200, height: 200))

        // Decoding it again would buy nothing: the frames are already smaller
        // than the view.
        #expect(view.player === player)
    }

    @Test func neverScalesTheFramesUp() async throws {
        layOut(CGSize(width: 200, height: 200))

        await display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 8, height: 8)))

        let player = try #require(view.player)
        await player.buffer.waitUntilFull()
        let frame = try #require(player.image?.cgImage)
        #expect(frame.width == 8)
    }

    @Test func downsamplingCanBeTurnedOff() async throws {
        view.isAutomaticDownsamplingEnabled = false
        layOut(CGSize(width: 20, height: 20))

        await display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))

        #expect(try #require(view.player).options.maxPixelSize == nil)
    }

    @Test func aSizeOfYourOwnWins() async throws {
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 64
        view.playerOptions = options
        layOut(CGSize(width: 20, height: 20))

        await display(Test.animatedGIF(frameCount: 2, size: CGSize(width: 400, height: 400)))

        #expect(try #require(view.player).options.maxPixelSize == 64)
    }

    // MARK: Playback and the Window

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
        await player.buffer.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 8)

        view.removeFromSuperview()

        // Off screen, the animation is worth two frames, not a whole budget.
        #expect(player.diagnostics.bufferedFrameCount == AnimatedImageFrameBuffer.idleCapacity)
        host.close()
    }

    @Test func keepsTheBufferWhenPlaybackIsPausedInPlace() async throws {
        let host = TestWindow(view: view)
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 8)))
        let player = try #require(view.player)
        await player.buffer.waitUntilFull()

        view.isPlaybackEnabled = false

        // Still on screen: resuming should not have to decode it all again.
        #expect(player.isPlaying == false)
        #expect(player.diagnostics.bufferedFrameCount == 8)
        host.close()
    }

    @Test func playsOutsideAWindowWhenAsked() throws {
        view.isPlaybackPausedWhenOffscreen = false
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF()))

        #expect(view.isPlaying)
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
        await player.buffer.waitUntilFull()

        view.player = player

        // The frame the player already has is displayed immediately.
        #expect(view.image != nil)
    }

#if os(macOS)
    // MARK: AppKit

    @Test func doesNotLetAppKitPlayTheImage() {
        // `NSImageView.animates` is on by default and plays a multi-frame
        // `NSImage` on a timer of its own – beside the player, and under a view
        // that is meant to be holding a still.
        #expect(view.animates == false)
    }

    @Test func coversTheViewWithTheFrames() throws {
        // `NSImageView` has no aspect-fill scaling mode – every value of
        // `imageScaling` fits – so the view draws that one itself.
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        view.image = wideImage()

        view.isAspectFillEnabled = true

        // A 4:1 image covering a square view leaves the middle quarter of it
        // on screen, which straddles the green and blue bands.
        #expect(try corners(of: view) == [.green, .blue, .green, .blue])
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
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.addSubview(view)
        window.isHidden = false
    }

    func close() {
        window.isHidden = true
    }
#endif
}

#endif

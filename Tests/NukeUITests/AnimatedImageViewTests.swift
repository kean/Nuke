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

    // MARK: Displaying

    @Test func playsAnimatedData() async throws {
        view.nuke_display(image: Test.image, data: Test.animatedGIF())

        let player = try #require(view.player)
        #expect(player.source.frameCount == 4)
        await player.buffer.waitUntilFull()
        #expect(view.image != nil)
    }

    @Test func showsStillImageForNonAnimatedData() {
        view.nuke_display(image: Test.image, data: nil)

        #expect(view.player == nil)
        #expect(view.animatedImage == nil)
        #expect(view.image != nil)
    }

    @Test func showsStillImageForSingleFrameGIF() {
        // Every GIF arrives with its data attached, so a still one has to be
        // recognized here rather than turned into a one-frame animation.
        view.nuke_display(image: Test.image, data: Test.animatedGIF(frameCount: 1))

        #expect(view.player == nil)
        #expect(view.image != nil)
    }

    @Test func showsThePosterFrameBeforeTheFirstFrameIsDecoded() {
        let poster = Test.image

        view.nuke_display(image: poster, data: Test.animatedGIF())

        // The still the decoder produced is on screen right away; the player
        // replaces it when it has a frame of its own.
        #expect(view.image === poster)
    }

    @Test func replacesThePreviousAnimation() async throws {
        view.nuke_display(image: Test.image, data: Test.animatedGIF(frameCount: 4))
        let first = try #require(view.player)

        view.nuke_display(image: Test.image, data: Test.animatedGIF(frameCount: 6))

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

    @Test func prepareForReuseStopsEverything() throws {
        view.nuke_display(image: Test.image, data: Test.animatedGIF())
        let player = try #require(view.player)

        view.prepareForReuse()

        #expect(view.player == nil)
        #expect(view.animatedImage == nil)
        #expect(view.image == nil)
        #expect(player.isPlaying == false)
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

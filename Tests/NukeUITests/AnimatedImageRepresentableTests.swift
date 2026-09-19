// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import SwiftUI
import Testing
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

/// Covers what ``AnimatedImage`` does with the ``AnimatedImageView`` it wraps:
/// the animation it hands it, the size it lays it out at, and what happens as
/// SwiftUI reconfigures it and takes it on and off screen.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageRepresentableTests {
    // MARK: Containers

    @Test func playsTheAnimationOfAContainerAndHoldsItsStillUntilTheFirstFrame() async throws {
        let data = Test.animatedGIF(frameCount: 4)
        let parsed = try #require(AnimatedImageSource(data: data))
        let decoder = GatedFrameDecoder(source: parsed)
        // A decoder that hands the frames over when the test says so, which
        // is what keeps the still on screen for as long as the test looks.
        let gated = AnimatedImageSource(
            data: data,
            delays: parsed.delays,
            size: parsed.size,
            makeFrameDecoder: { _ in decoder }
        )
        let source = try #require(gated)
        let poster = Test.image
        var container = ImageContainer(image: poster, data: data)
        container.animation = source

        let animation = try #require(AnimatedImage(container: container))
        let host = ViewHost(animation) { $0 }
        await render(host, until: { host.firstView(ofType: AnimatedImageView.self)?.player != nil })

        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        #expect(view.animatedImage === source)
        #expect(view.image === poster)

        for index in 0..<4 { await decoder.release(index) }
        await render(host, until: { view.image !== poster })

        #expect(view.image === view.player?.image)
    }

    @Test func hasNothingToPlayForAContainerThatIsNotAnimated() {
        // The signal to display the still: the data alone is not an
        // animation, only what the pipeline parsed out of it.
        let container = ImageContainer(image: Test.image, data: Test.animatedGIF())

        #expect(AnimatedImage(container: container) == nil)
    }

    // MARK: Layout

    @Test func takesItsNaturalSizeAtTheScaleOfThePlayer() async throws {
        let source = Test.animatedGIFSource(size: CGSize(width: 40, height: 20))
        var options = AnimatedImagePlayer.Options()
        options.scale = 2
        let player = AnimatedImagePlayer(source: source, options: options)
        let expected = CGSize(width: 20, height: 10)

        let host = ViewHost(player) { AnimatedImage(player: $0) }
        await render(host, until: { host.firstView(ofType: AnimatedImageView.self)?.bounds.size == expected })

        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        #expect(view.bounds.size == expected)
    }

    @Test func aResizableAnimationFitsInsideTheSpaceItIsOffered() async throws {
        // The host offers 200×200; a 2:1 animation takes the width and half
        // the height, the way `Image.resizable().scaledToFit()` would.
        let source = Test.animatedGIFSource(size: CGSize(width: 40, height: 20))
        let expected = CGSize(width: 200, height: 100)

        let host = ViewHost(source) { AnimatedImage($0).resizable() }
        await render(host, until: { host.firstView(ofType: AnimatedImageView.self)?.bounds.size == expected })

        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        #expect(view.bounds.size == expected)
    }

    // MARK: Updates

    @Test func playsTheNewAnimationWhenItIsReconfigured() async throws {
        // SwiftUI keeps the platform view when the image behind it changes,
        // and the view has to let go of the animation it was given first.
        let first = Test.animatedGIFSource(frameCount: 4)
        let second = Test.animatedGIFSource(frameCount: 6)
        let host = ViewHost(first) { AnimatedImage($0) }
        await render(host, until: { host.firstView(ofType: AnimatedImageView.self)?.player != nil })
        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        let replaced = try #require(view.player)

        await host.update(second, until: { view.player?.source === second })
        await render(host, until: { view.player?.source === second })

        #expect(host.firstView(ofType: AnimatedImageView.self) === view)
        #expect(view.player?.source === second)
        #expect(replaced.isPlaying == false)
    }

    @Test func pausesOffScreenAndResumesWhenItComesBack() async throws {
        let source = Test.animatedGIFSource(frameCount: 8)
        let host = ViewHost(source) { AnimatedImage($0) }
        await render(host, until: { host.firstView(ofType: AnimatedImageView.self)?.isPlaying == true })
        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        let player = try #require(view.player)

        await host.hideContent(until: { player.isPlaying == false })
        await render(host, until: { player.isPlaying == false })
        #expect(player.isPlaying == false)

        await host.showContent(until: { player.isPlaying })
        await render(host, until: { player.isPlaying })

        #expect(view.player === player)
        #expect(player.isPlaying)
    }

    // MARK: Helpers

    /// Renders until the condition holds, for longer than one
    /// `render(until:)`, which gives up after a fifth of a second: SwiftUI
    /// and the decoder each take turns of their own, and on a loaded machine
    /// they can take longer than that.
    private func render<Value, Content>(_ host: ViewHost<Value, Content>, until condition: () -> Bool) async {
        for _ in 0..<25 where !condition() {
            await host.render(until: condition)
        }
    }
}

#endif

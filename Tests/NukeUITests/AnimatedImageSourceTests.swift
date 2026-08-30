// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

@Suite(.timeLimit(.minutes(5)))
struct AnimatedImageSourceTests {
    // MARK: Parsing

    @Test func parsesGIF() throws {
        let data = Test.animatedGIF(frameCount: 5, delays: Array(repeating: 0.05, count: 5), size: CGSize(width: 12, height: 9))
        let source = try #require(AnimatedImageSource(data: data))

        #expect(source.frameCount == 5)
        #expect(source.type == .gif)
        #expect(source.delays == Array(repeating: 0.05, count: 5))
        #expect(source.duration == 0.25)
        #expect(source.loopCount == 0)
        #expect(source.size == CGSize(width: 12, height: 9))
    }

    @Test func parsesAPNG() throws {
        guard let data = Test.animatedPNG(frameCount: 3, delays: [0.1, 0.2, 0.3]) else {
            return // Image I/O on this platform can't write an APNG
        }
        let source = try #require(AnimatedImageSource(data: data))

        #expect(source.frameCount == 3)
        #expect(source.type == .png)
        #expect(source.delays.count == 3)
        #expect(abs(source.duration - 0.6) < 0.001)
    }

    @Test func parsesTheFixture() throws {
        let source = try #require(AnimatedImageSource(data: Test.data(name: "cat", extension: "gif")))

        #expect(source.frameCount > 1)
        #expect(source.duration > 0)
        #expect(source.size.width > 0)
        #expect(source.delays.count == source.frameCount)
    }

    @Test func readsLoopCount() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(loopCount: 3)))
        #expect(source.loopCount == 3)
    }

    @Test func readsPerFrameDelays() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 3, delays: [0.02, 0.5, 0.2])))
        #expect(source.delays == [0.02, 0.5, 0.2])
    }

    // MARK: Delay Corrections

    @Test func replacesDelaysBelowTheThresholdWithTheDefault() throws {
        // A GIF asking for 10 ms a frame is a GIF that means "as fast as
        // possible", and every browser plays it at 100 ms instead.
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 2, delays: [0.01, 0.01])))
        #expect(source.delays == [0.1, 0.1])
    }

    @Test func keepsDelaysAtTheThreshold() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 2, delays: [0.02, 0.02])))
        #expect(source.delays == [0.02, 0.02])
    }

    // MARK: Rejecting Non-Animations

    @Test func returnsNilForStaticImage() {
        #expect(AnimatedImageSource(data: Test.staticPNG()) == nil)
        #expect(AnimatedImageSource(data: Test.data) == nil)
    }

    @Test func returnsNilForSingleFrameGIF() {
        // The pipeline attaches the data of every GIF, animated or not, so the
        // one-frame case is the one the views hit most often.
        #expect(AnimatedImageSource(data: Test.animatedGIF(frameCount: 1)) == nil)
    }

    @Test func returnsNilForGarbage() {
        #expect(AnimatedImageSource(data: Data()) == nil)
        #expect(AnimatedImageSource(data: Data(repeating: 0x11, count: 128)) == nil)
    }

    @Test func returnsNilForContainerWithoutData() {
        #expect(AnimatedImageSource(container: Test.container) == nil)
    }

    @Test func parsesContainerWithData() throws {
        let data = Test.animatedGIF()
        let container = ImageContainer(image: Test.image, type: .gif, data: data)
        let source = try #require(AnimatedImageSource(container: container))
        #expect(source.frameCount == 4)
    }

    // MARK: Caching

    @Test func reusesTheParsedAnimationForTheSameData() throws {
        let container = ImageContainer(image: Test.image, type: .gif, data: Test.animatedGIF())

        let first = try #require(AnimatedImageSource.cached(container: container))
        let second = try #require(AnimatedImageSource.cached(container: container))

        // Parsing walks the metadata of every frame, and a list scrolled back
        // to an animation displays the same data again.
        #expect(first === second)
    }

    @Test func parsesEachAnimationOnItsOwn() throws {
        let first = try #require(AnimatedImageSource.cached(data: Test.animatedGIF(frameCount: 4)))
        let second = try #require(AnimatedImageSource.cached(data: Test.animatedGIF(frameCount: 6)))

        #expect(first !== second)
        #expect(second.frameCount == 6)
    }

    @Test func cachingReturnsNilForDataThatIsNotAnimated() {
        #expect(AnimatedImageSource.cached(data: Test.data) == nil)
        #expect(AnimatedImageSource.cached(container: Test.container) == nil)
    }

    @Test func remembersThatDataIsNotAnimated() {
        // A single-frame GIF still arrives with its data attached – whether it
        // is animated is what the parse answers – so a list of static GIFs
        // would pay for the scan on every cell without this.
        let data = Test.animatedGIF(frameCount: 1)

        #expect(AnimatedImageSource.cached(data: data) == nil)

        #expect(AnimatedImageSourceCache.shared.isKnownStatic(data))
    }

    // MARK: Derived Values

    @Test func computesFrameRateAndFrameSize() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(
            frameCount: 4,
            delays: Array(repeating: 0.05, count: 4),
            size: CGSize(width: 10, height: 20)
        )))

        #expect(source.nominalFrameRate == 20)
        #expect(source.bytesPerFrame == 10 * 20 * 4)
    }
}

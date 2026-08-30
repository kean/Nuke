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

    @Test func parsesAnimatedHEIC() throws {
        guard let data = Test.animatedHEICS(frameCount: 3, delays: [0.25, 0.25, 0.25]) else {
            return // Image I/O on this platform can't write a HEIC sequence
        }
        let source = try #require(AnimatedImageSource(data: data))

        #expect(source.frameCount == 3)
        #expect(source.type == .heic)
        // Read from the container, not defaulted: the delays a sequence
        // declares used to be missed because `CGImageSourceGetType` reports it
        // as `public.heics` and the format was matched on `public.heic`, which
        // left every frame on the 0.1 s fallback.
        #expect(source.delays == [0.25, 0.25, 0.25])
        // The loop count is not asserted: Image I/O's HEICS encoder reads back
        // `1` whatever it is asked to write, so there is nothing to compare to.
    }

    @Test func parsesAnimatedWebP() throws {
        // The one format Image I/O can't write, so the fixture is a file: four
        // 8×8 frames at 0.1 s, looping forever.
        let source = try #require(AnimatedImageSource(data: Test.data(name: "animated", extension: "webp")))

        #expect(source.frameCount == 4)
        #expect(source.type == .webp)
        #expect(source.delays == Array(repeating: 0.1, count: 4))
        #expect(source.loopCount == 0)
        #expect(source.size == CGSize(width: 8, height: 8))
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

    @Test func remembersThatDataIsNotAnimated() throws {
        // A single-frame GIF still arrives with its data attached – whether it
        // is animated is what the parse answers – so a list of static GIFs
        // would pay for the scan on every cell without this.
        let data = Test.animatedGIF(frameCount: 1)

        #expect(AnimatedImageSource.cached(data: data) == nil)

        let parsed = try #require(AnimatedImageSourceCache.shared.parsed(for: data))
        #expect(parsed == nil)
    }

    @Test @MainActor func parsesDataItHasNotSeenBeforeOffTheMainThread() async throws {
        let frameCount = unseenFrameCount()
        let data = Test.animatedGIF(frameCount: frameCount)

        var task: Task<Void, Never>?
        let source = await withCheckedContinuation { continuation in
            task = AnimatedImageSource.parse(data: data) {
                continuation.resume(returning: $0)
            }
        }

        // A task rather than an answer: there was nothing parsed to hand back,
        // and counting the frames of a large animation is a frame's worth of
        // main-thread time.
        #expect(task != nil)
        #expect(source?.frameCount == frameCount)

        // Now that it is parsed, the answer comes back without a hop.
        let again = AnimatedImageSource.parse(data: data) { _ in }
        #expect(again == nil)
    }

    /// A frame count nothing has parsed yet, so that the cache really is being
    /// asked about the animation for the first time – including when the suite
    /// runs more than once in a process.
    @MainActor private func unseenFrameCount() -> Int {
        AnimatedImageSourceTests.unseenFrameCounts += 1
        return AnimatedImageSourceTests.unseenFrameCounts
    }

    @MainActor private static var unseenFrameCounts = 19

    @Test func tellsApartDataThatSharesALongPrefix() {
        // Two animations from the same encoder at the same size are identical
        // for far more than the 80 bytes `NSData` hashes: the signature, the
        // screen descriptor, the palette. Every lookup in a list of them
        // collided and `NSCache` fell through to comparing the contents in
        // full – a memcmp of the whole animation, per cell displayed.
        let shared = Data(repeating: 0xAB, count: 512)
        let first = shared + Data([0x01])
        let second = shared + Data([0x02])
        #expect((first as NSData).hash == (second as NSData).hash) // The old key

        #expect(AnimatedImageDataKey(first).hash != AnimatedImageDataKey(second).hash)
        #expect(AnimatedImageDataKey(first) == AnimatedImageDataKey(first))
        #expect(AnimatedImageDataKey(first) != AnimatedImageDataKey(second))
    }

    @Test func tellsApartDataOfTheSameLengthThatDiffersInTheMiddle() {
        var first = Data(repeating: 0xAB, count: 1024)
        var second = first
        first[500] = 0x01
        second[500] = 0x02

        // Equality is the contents in full, so a hash that misses the
        // difference is only ever slow, never wrong.
        #expect(AnimatedImageDataKey(first) != AnimatedImageDataKey(second))
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

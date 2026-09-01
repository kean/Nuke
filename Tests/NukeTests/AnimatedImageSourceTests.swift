// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Nuke

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

    // MARK: Decoding Frames

    @Test func makesAnImageSourceForDecodingTheFrames() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4)))
        let imageSource = try #require(source.makeImageSource())

        #expect(CGImageSourceGetCount(imageSource) == 4)
        #expect(CGImageSourceCreateImageAtIndex(imageSource, 2, AnimatedImageSource.imageSourceOptions) != nil)
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

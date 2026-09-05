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
        #expect(source.delays.count == 3)
        #expect(abs(source.duration - 0.6) < 0.001)
    }

    @Test func parsesAnimatedHEIC() throws {
        guard let data = Test.animatedHEICS(frameCount: 3, delays: [0.25, 0.25, 0.25]) else {
            return // Image I/O on this platform can't write a HEIC sequence
        }
        let source = try #require(AnimatedImageSource(data: data))

        #expect(source.frameCount == 3)
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
        #expect(source.delays == Array(repeating: 0.1, count: 4))
        #expect(source.loopCount == 0)
        #expect(source.size == CGSize(width: 8, height: 8))
    }

    @Test func parsesAnimatedAVIF() throws {
        // Image I/O decodes `public.avis` but only encodes the still flavor,
        // so the fixture is a file: three 8×8 frames at 0.25 s, 0.05 s, and
        // 0.2 s.
        let source = try #require(AnimatedImageSource(data: Test.data(name: "animated", extension: "avif")))

        #expect(source.frameCount == 3)
        // Read from the `{AVIS}` container, not defaulted: the format used to
        // be missing from `AnimatedImageFormat` altogether, which left every
        // frame on the 0.1 s fallback. The middle frame is the one that shows
        // it – Image I/O clamps it to exactly the fallback and files the
        // value the file asks for under the unclamped key.
        #expect(source.delays == [0.25, 0.05, 0.2])
        #expect(abs(source.duration - 0.5) < 0.001)
        #expect(source.size == CGSize(width: 8, height: 8))
        // The loop count is not asserted: an AVIF sequence has nowhere to put
        // one, so Image I/O reports `0` – the same value the fallback gives.
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

    @Test func readsAGIFWithNoLoopExtensionAsPlayOnce() throws {
        // A GIF stores its loop count in the Netscape application extension,
        // and a GIF without that block plays once in every browser. Treating
        // the missing count as "forever" is the one place the file and the
        // player disagree.
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(loopCount: nil)))
        #expect(source.loopCount == 1)
    }

    @Test func defaultsTheLoopCountPerFormat() {
        // Image I/O fills the count in for a GIF written without the extension
        // on some releases, so the fallback is asserted directly: "play once"
        // is a GIF rule, and every other format keeps looping forever.
        #expect(AnimatedImageFormat.gif.loopCount(in: [kCGImagePropertyGIFDictionary: [:] as [CFString: Any]]) == 1)
        #expect(AnimatedImageFormat.png.loopCount(in: [kCGImagePropertyPNGDictionary: [:] as [CFString: Any]]) == 0)
        #expect(AnimatedImageFormat.webp.loopCount(in: [kCGImagePropertyWebPDictionary: [:] as [CFString: Any]]) == 0)
        // A declared count is read whatever the format, `0` – forever –
        // included.
        #expect(AnimatedImageFormat.gif.loopCount(in: [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0] as [CFString: Any]
        ]) == 0)
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

    @Test func returnsNilForAMultiFrameImageThatDeclaresNoAnimation() throws {
        // A page stack is not an animation: it has several frames and no
        // animation metadata, which is what WebKit tests for too – no
        // container dictionary means no repetition count, and an image with no
        // repetition count is never played. Read as one, a two-page TIFF would
        // flip between its pages at the 0.1 s fallback, forever.
        let data = Test.multiPageTIFF(pageCount: 2)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        #expect(AnimatedImageSource(data: data) == nil)
    }

    @Test func returnsNilForGarbage() {
        #expect(AnimatedImageSource(data: Data()) == nil)
        #expect(AnimatedImageSource(data: Data(repeating: 0x11, count: 128)) == nil)
    }

    // MARK: Animations Image I/O Can't Read

    @Test func describesAnAnimationTheCallerParsed() throws {
        // The format Image I/O has never heard of, described by the decoder
        // that can read it.
        let data = Flipbook.encode(frameCount: 4, delays: [0.2, 0.2, 0.2, 0.2], loopCount: 3, size: CGSize(width: 16, height: 12))
        #expect(AnimatedImageSource(data: data) == nil)
        let flipbook = try #require(Flipbook(data: data))

        let made = AnimatedImageSource(
            data: data,
            delays: flipbook.delays,
            loopCount: flipbook.loopCount,
            size: flipbook.size,
            makeFrameDecoder: { FlipbookFrameDecoder(flipbook, maxPixelSize: $0) }
        )
        let source = try #require(made)

        #expect(source.data == data)
        #expect(source.frameCount == 4) // Counted from the delays
        #expect(source.delays == Array(repeating: 0.2, count: 4))
        #expect(source.duration == 0.8)
        #expect(source.loopCount == 3)
        #expect(source.size == CGSize(width: 16, height: 12))
        #expect(source.nominalFrameRate == 5)
        #expect(source.makeFrameDecoder() is FlipbookFrameDecoder)
    }

    @Test func correctsTheDelaysItIsGivenTheWayItCorrectsTheOnesItParses() throws {
        // The same two corrections every browser applies, so an animation the
        // caller describes plays like one Image I/O describes.
        let made = AnimatedImageSource(
            data: Data(),
            delays: [0, -1, 0.005, 0.2],
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { FlipbookFrameDecoder(Flipbook(data: Flipbook.encode())!, maxPixelSize: $0) }
        )
        let source = try #require(made)

        #expect(source.delays == [0.1, 0.1, 0.1, 0.2])
    }

    @Test func refusesWhatIsNotAnAnimation() {
        let flipbook = Flipbook(data: Flipbook.encode())!
        func makeSource(delays: [TimeInterval], size: CGSize) -> AnimatedImageSource? {
            AnimatedImageSource(
                data: Data(),
                delays: delays,
                size: size,
                makeFrameDecoder: { _ in FlipbookFrameDecoder(flipbook) }
            )
        }
        let size = CGSize(width: 8, height: 8)

        // A single frame is a still image, and a canvas with no pixels in it
        // is nothing at all.
        #expect(makeSource(delays: [], size: size) == nil)
        #expect(makeSource(delays: [0.1], size: size) == nil)
        #expect(makeSource(delays: [0.1, 0.1], size: .zero) == nil)
        #expect(makeSource(delays: [0.1, 0.1], size: size) != nil)
    }

    // MARK: Decoding Frames

    @Test func decodesWithImageIOWhenNoDecoderWasGiven() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4)))

        #expect(source.makeFrameDecoder() is AnimatedImageFrameDecoder)
    }

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

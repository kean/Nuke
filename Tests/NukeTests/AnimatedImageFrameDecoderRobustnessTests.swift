// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Nuke

/// What the Image I/O frame decoder does with the requests a player – or a
/// renderer of your own – shouldn't make but can: cancelled ones, indexes that
/// aren't there, limits that aren't sizes, and many at once.
@Suite(.timeLimit(.minutes(5)))
struct AnimatedImageFrameDecoderRobustnessTests {

    // MARK: Cancellation

    @Test func cancelledRequestProducesNoFrame() async throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 3)))
        let decoder = AnimatedImageFrameDecoder(source: source)

        let frame = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await decoder.decode(at: 0)
        }.value

        #expect(frame == nil)
    }

    @Test func cancelledRequestDoesNotBreakTheDecoder() async throws {
        // The first request is also the one that creates the image source: a
        // cancelled one must not leave the decoder without it.
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 3)))
        let decoder = AnimatedImageFrameDecoder(source: source)
        _ = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await decoder.decode(at: 0)
        }.value

        let frame = await decoder.decode(at: 0)

        #expect(frame != nil)
    }

    // MARK: Indexes

    @Test(arguments: [-1, 3, Int.max, Int.min])
    func indexOutsideTheAnimationProducesNoFrame(index: Int) async throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 3)))
        let decoder = AnimatedImageFrameDecoder(source: source)

        #expect(await decoder.decode(at: index) == nil)
        // ...and leaves the decoder working
        #expect(await decoder.decode(at: 2) != nil)
    }

    // MARK: Limits

    @Test(arguments: [CGFloat.nan, .infinity, -.infinity, .greatestFiniteMagnitude, 0, -1, 0.4])
    func limitThatIsNotAPixelSizeStillProducesAFrame(maxPixelSize: CGFloat) async throws {
        // `Int(_:)` traps on NaN and on the infinities, and a limit under one
        // pixel can't be met by any frame. None of these may stop playback.
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(size: CGSize(width: 12, height: 6))))

        let frame = try #require(await AnimatedImageFrameDecoder(source: source, maxPixelSize: maxPixelSize).decode(at: 1))

        #expect(frame.width <= 12)
        #expect(frame.height <= 6)
        if !maxPixelSize.isFinite || maxPixelSize > 12 {
            // No limit at all, which means the size the animation is stored at
            #expect(CGSize(width: frame.width, height: frame.height) == source.size)
        }
    }

    @Test func limitIsRoundedToAWholePixel() async throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(size: CGSize(width: 40, height: 20))))

        let frame = try #require(await AnimatedImageFrameDecoder(source: source, maxPixelSize: 9.6).decode(at: 0))

        #expect(frame.width == 10)
        #expect(frame.height == 5)
    }

    // MARK: Concurrency

    @Test func concurrentRequestsGetTheFramesTheyAskedFor() async throws {
        // The decoder is an actor over a `CGImageSource`, which isn't safe to
        // use concurrently: every request has to come back with its own frame.
        let frameCount = 6
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: frameCount, size: CGSize(width: 4, height: 4))))
        let reference = try #require(source.makeImageSource())
        let expected = try (0..<frameCount).map { index in
            let frame = try #require(CGImageSourceCreateImageAtIndex(reference, index, nil))
            return try #require(Test.firstPixel(of: frame))
        }
        let decoder = AnimatedImageFrameDecoder(source: source)

        let decoded = await withTaskGroup(of: (Int, [UInt8]?).self) { group in
            for request in 0..<(frameCount * 8) {
                let index = (request * 5) % frameCount
                group.addTask {
                    let frame = await decoder.decode(at: index)
                    return (index, frame.flatMap(Test.firstPixel))
                }
            }
            return await group.reduce(into: [(Int, [UInt8]?)]()) { $0.append($1) }
        }

        #expect(decoded.count == frameCount * 8)
        for (index, pixel) in decoded {
            #expect(pixel == expected[index], "Frame \(index)")
        }
    }
}

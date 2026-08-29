// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageFrameBufferTests {
    // MARK: Capacity

    @Test func holdsEveryFrameWhenTheAnimationFitsInTheBudget() throws {
        let source = try makeSource(frameCount: 12, size: CGSize(width: 32, height: 32))
        let buffer = AnimatedImageFrameBuffer(source: source, options: AnimatedImagePlayer.Options())

        #expect(buffer.capacity == 12)
    }

    @Test func windowsTheFramesWhenTheAnimationDoesNotFit() throws {
        let source = try makeSource(frameCount: 20, size: CGSize(width: 32, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 5 * source.bytesPerFrame

        let buffer = AnimatedImageFrameBuffer(source: source, options: options)

        #expect(buffer.capacity == 5)
    }

    @Test func neverGoesBelowTwoFrames() throws {
        // One frame would mean the next one can only start decoding after the
        // current one is dropped, which stalls playback on every frame.
        let source = try makeSource(frameCount: 20, size: CGSize(width: 32, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 1

        let buffer = AnimatedImageFrameBuffer(source: source, options: options)

        #expect(buffer.capacity == 2)
    }

    @Test func countsDownsamplingAgainstTheBudget() throws {
        let source = try makeSource(frameCount: 40, size: CGSize(width: 64, height: 64))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 4 * source.bytesPerFrame
        options.maxPixelSize = 32 // A quarter of the pixels, so four times the frames

        let buffer = AnimatedImageFrameBuffer(source: source, options: options)

        #expect(buffer.capacity == 16)
    }

    // MARK: Decoding

    @Test func decodesTheWholeWindow() async throws {
        let source = try makeSource(frameCount: 6)
        let buffer = AnimatedImageFrameBuffer(source: source, options: AnimatedImagePlayer.Options())

        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()

        #expect(buffer.count == 6)
        #expect(buffer.isFull)
        #expect(buffer.decodedFrameCount == 6)
        #expect(buffer.byteCount > 0)
        for index in 0..<6 {
            #expect(buffer.frame(at: index) != nil)
        }
    }

    @Test func decodesOnlyTheWindowWhenItIsSmallerThanTheAnimation() async throws {
        let source = try makeSource(frameCount: 8, size: CGSize(width: 32, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 3 * source.bytesPerFrame
        let buffer = AnimatedImageFrameBuffer(source: source, options: options)

        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()

        #expect(buffer.count == 3)
        #expect(buffer.frame(at: 0) != nil)
        #expect(buffer.frame(at: 2) != nil)
        #expect(buffer.frame(at: 3) == nil)
    }

    @Test func reportsEachFrameAsItArrives() async throws {
        let source = try makeSource(frameCount: 4)
        let buffer = AnimatedImageFrameBuffer(source: source, options: AnimatedImagePlayer.Options())
        var decoded: [Int] = []
        buffer.onFrame = { decoded.append($0) }

        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()

        // In playback order, which is what makes the first frames appear first.
        #expect(decoded == [0, 1, 2, 3])
    }

    @Test func decodesTheFramesAheadOfTheCurrentOne() async throws {
        let source = try makeSource(frameCount: 8, size: CGSize(width: 32, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 3 * source.bytesPerFrame
        let buffer = AnimatedImageFrameBuffer(source: source, options: options)

        buffer.setCurrentIndex(6)
        await buffer.waitUntilFull()

        #expect(buffer.frame(at: 6) != nil)
        #expect(buffer.frame(at: 7) != nil)
        #expect(buffer.frame(at: 0) != nil) // The window wraps around
        #expect(buffer.frame(at: 1) == nil)
    }

    // MARK: Eviction

    @Test func dropsTheFramesTheWindowHasMovedPast() async throws {
        let source = try makeSource(frameCount: 8, size: CGSize(width: 32, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 3 * source.bytesPerFrame
        let buffer = AnimatedImageFrameBuffer(source: source, options: options)
        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()

        buffer.setCurrentIndex(3)
        await buffer.waitUntilFull()

        #expect(buffer.frame(at: 0) == nil)
        #expect(buffer.frame(at: 3) != nil)
        #expect(buffer.count == 3)
    }

    @Test func keepsEveryFrameWhenTheWholeAnimationFits() async throws {
        let source = try makeSource(frameCount: 5)
        let buffer = AnimatedImageFrameBuffer(source: source, options: AnimatedImagePlayer.Options())
        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()

        buffer.setCurrentIndex(4)
        await buffer.waitUntilFull()

        #expect(buffer.count == 5)
        // Nothing was evicted, so nothing had to be decoded twice.
        #expect(buffer.decodedFrameCount == 5)
    }

    @Test func reduceCapacityDropsFrames() async throws {
        let source = try makeSource(frameCount: 8)
        let buffer = AnimatedImageFrameBuffer(source: source, options: AnimatedImagePlayer.Options())
        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()
        #expect(buffer.count == 8)

        buffer.reduceCapacity(to: 2)

        #expect(buffer.capacity == 2)
        #expect(buffer.count == 2)
        #expect(buffer.frame(at: 0) != nil)
        #expect(buffer.frame(at: 1) != nil)
        #expect(buffer.frame(at: 2) == nil)
    }

    @Test func reduceCapacityNeverGrowsTheBuffer() async throws {
        let source = try makeSource(frameCount: 4)
        let buffer = AnimatedImageFrameBuffer(source: source, options: AnimatedImagePlayer.Options())

        buffer.reduceCapacity(to: 100)

        #expect(buffer.capacity == 4)
    }

    @Test func removeAllClearsTheBuffer() async throws {
        let source = try makeSource(frameCount: 4)
        let buffer = AnimatedImageFrameBuffer(source: source, options: AnimatedImagePlayer.Options())
        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()

        buffer.removeAll()

        #expect(buffer.count == 0)
        #expect(buffer.byteCount == 0)
        #expect(buffer.frame(at: 0) == nil)
    }

    // MARK: Downsampling

    @Test func downsamplesTheFrames() async throws {
        let source = try makeSource(frameCount: 2, size: CGSize(width: 64, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 16
        let buffer = AnimatedImageFrameBuffer(source: source, options: options)

        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()

        let frame = try #require(buffer.frame(at: 0))
        #expect(frame.width == 16)
        #expect(frame.height == 8)
    }

    @Test func doesNotUpscaleSmallFrames() async throws {
        let source = try makeSource(frameCount: 2, size: CGSize(width: 8, height: 8))
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 512
        let buffer = AnimatedImageFrameBuffer(source: source, options: options)

        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()

        let frame = try #require(buffer.frame(at: 0))
        #expect(frame.width == 8)
    }

    // MARK: Damaged Data

    @Test func doesNotSpinOnFramesItCannotDecode() async throws {
        // A truncated animation: the header promises frames the data doesn't
        // contain. Retrying them forever would peg a core.
        let data = Test.animatedGIF(frameCount: 8, size: CGSize(width: 32, height: 32))
        guard let source = AnimatedImageSource(data: data.prefix(data.count / 2)) else {
            return // Too little of the animation survived to be worth the test
        }
        let buffer = AnimatedImageFrameBuffer(source: source, options: AnimatedImagePlayer.Options())

        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()

        #expect(buffer.isFull) // Nothing left to try, decoded or not
    }

    // MARK: Helpers

    private func makeSource(frameCount: Int, size: CGSize = CGSize(width: 8, height: 8)) throws -> AnimatedImageSource {
        try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: frameCount, size: size)))
    }
}

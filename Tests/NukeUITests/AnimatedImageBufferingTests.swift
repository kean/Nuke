// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

/// The window of decoded frames a player holds: how large it is, what goes into
/// it, and what falls out of it.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageBufferingTests {
    /// A pool of its own for every test: what a player is allowed to hold
    /// depends on what every other animation on screen is asking for, and the
    /// suite runs beside every other one.
    private let pool = AnimatedImageFramePool()

    // MARK: Capacity

    @Test func holdsEveryFrameWhenTheAnimationFitsInTheBudget() throws {
        let player = try makePlayer(frameCount: 12, size: CGSize(width: 32, height: 32))

        #expect(player.diagnostics.bufferCapacity == 12)
    }

    @Test func keepsTheReadAheadWhenTheAnimationDoesNotFit() throws {
        // Ten frames' worth of budget buys the same as five would: a window
        // that slides re-decodes every frame each loop however long it is, so
        // the player keeps the frame on screen and the read-ahead and leaves
        // the rest.
        let source = try makeSource(frameCount: 20, size: CGSize(width: 32, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 10 * source.bytesPerFrame

        let player = makePlayer(source: source, options: options)

        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func neverGoesBelowTwoFrames() throws {
        // One frame would mean the next one can only start decoding after the
        // current one is dropped, which stalls playback on every frame.
        let source = try makeSource(frameCount: 20, size: CGSize(width: 32, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 1

        let player = makePlayer(source: source, options: options)

        #expect(player.diagnostics.bufferCapacity == 2)
    }

    @Test func countsDownsamplingAgainstTheBudget() throws {
        // Four frames' worth of budget for sixteen frames: only downsampled to
        // a quarter of the pixels do they all fit. The downsampled player goes
        // first, because a player that asks for less than one already playing
        // draws from that player's frames instead of decoding its own.
        let source = try makeSource(frameCount: 16, size: CGSize(width: 64, height: 64))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 4 * source.bytesPerFrame
        options.maxPixelSize = 32
        let downsampled = makePlayer(source: source, options: options)
        #expect(downsampled.diagnostics.bufferCapacity == 16)

        options.maxPixelSize = nil
        let fullSize = makePlayer(source: source, options: options)

        #expect(fullSize.diagnostics.isFullyBuffered == false)
    }

    @Test func holdsTwoFramesUntilSomethingIsWatching() async throws {
        // A list of animations showing their first frame shouldn't each pin a
        // full window of bitmaps.
        let source = try makeSource(frameCount: 8)
        let player = AnimatedImagePlayer(source: source, options: AnimatedImagePlayer.Options(), clock: ManualClock(), pool: pool)

        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount)

        player.play()

        #expect(player.diagnostics.bufferCapacity == 8)
    }

    // MARK: Decoding

    @Test func decodesTheWholeWindow() async throws {
        let player = try makePlayer(frameCount: 6)

        await player.waitUntilFull()

        #expect(player.diagnostics.bufferedFrameCount == 6)
        #expect(player.diagnostics.decodedFrameCount == 6)
        #expect(player.diagnostics.bufferedByteCount > 0)
        for index in 0..<6 {
            #expect(player.isFrameBuffered(index))
        }
    }

    @Test func decodesOnlyTheWindowWhenItIsSmallerThanTheAnimation() async throws {
        let source = try makeSource(frameCount: 8, size: CGSize(width: 32, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 3 * source.bytesPerFrame
        let player = makePlayer(source: source, options: options)

        await player.waitUntilFull()

        #expect(player.diagnostics.bufferedFrameCount == 3)
        #expect(player.isFrameBuffered(0))
        #expect(player.isFrameBuffered(2))
        #expect(player.isFrameBuffered(3) == false)
    }

    @Test func decodesTheFramesAheadOfTheCurrentOne() async throws {
        let source = try makeSource(frameCount: 8, size: CGSize(width: 32, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 3 * source.bytesPerFrame
        let player = makePlayer(source: source, options: options)

        player.seek(toFrame: 6)
        await player.waitUntilFull()

        #expect(player.isFrameBuffered(6))
        #expect(player.isFrameBuffered(7))
        #expect(player.isFrameBuffered(0)) // The window wraps around
        #expect(player.isFrameBuffered(1) == false)
    }

    // MARK: Eviction

    @Test func dropsTheFramesTheWindowHasMovedPast() async throws {
        let source = try makeSource(frameCount: 8, size: CGSize(width: 32, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 3 * source.bytesPerFrame
        let player = makePlayer(source: source, options: options)
        await player.waitUntilFull()

        player.seek(toFrame: 3)
        await player.waitUntilFull()

        #expect(player.isFrameBuffered(0) == false)
        #expect(player.isFrameBuffered(3))
        #expect(player.diagnostics.bufferedFrameCount == 3)
    }

    @Test func keepsEveryFrameWhenTheWholeAnimationFits() async throws {
        let player = try makePlayer(frameCount: 5)
        await player.waitUntilFull()

        player.seek(toFrame: 4)
        await player.waitUntilFull()

        #expect(player.diagnostics.bufferedFrameCount == 5)
        // Nothing was evicted, so nothing had to be decoded twice.
        #expect(player.diagnostics.decodedFrameCount == 5)
    }

    @Test func memoryPressureDropsFrames() async throws {
        // Playback needs the frame on screen and the one being decoded, however
        // hard the system is asking for memory back.
        let player = try makePlayer(frameCount: 8)
        await player.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 8)

        pool.reduceMemoryUsage()

        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount)
        #expect(player.diagnostics.bufferedFrameCount == 2)
        #expect(player.isFrameBuffered(0))
        #expect(player.isFrameBuffered(1))
        #expect(player.isFrameBuffered(2) == false)
    }

    @Test func removeAllFramesClearsTheWindow() async throws {
        let player = try makePlayer(frameCount: 4)
        await player.waitUntilFull()

        player.store.removeAllFrames()

        #expect(player.diagnostics.bufferedFrameCount == 0)
        #expect(player.diagnostics.bufferedByteCount == 0)
        #expect(player.isFrameBuffered(0) == false)
    }

    // MARK: Downsampling

    @Test func downsamplesTheFrames() async throws {
        let source = try makeSource(frameCount: 2, size: CGSize(width: 64, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 16
        let player = makePlayer(source: source, options: options)

        await player.waitUntilFull()

        let frame = try #require(player.store.frame(at: 0))
        #expect(frame.width == 16)
        #expect(frame.height == 8)
    }

    @Test func doesNotUpscaleSmallFrames() async throws {
        let source = try makeSource(frameCount: 2, size: CGSize(width: 8, height: 8))
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 512
        let player = makePlayer(source: source, options: options)

        await player.waitUntilFull()

        let frame = try #require(player.store.frame(at: 0))
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
        let player = makePlayer(source: source)

        await player.waitUntilFull()

        #expect(player.store.currentDecode == nil) // Nothing left to try
    }

    // MARK: Helpers

    /// A player that is playing, which is what makes it ask for a full window
    /// of frames. One that isn't asks for two.
    private func makePlayer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options()
    ) -> AnimatedImagePlayer {
        let player = AnimatedImagePlayer(source: source, options: options, clock: ManualClock(), pool: pool)
        player.play()
        return player
    }

    private func makePlayer(
        frameCount: Int,
        size: CGSize = CGSize(width: 8, height: 8)
    ) throws -> AnimatedImagePlayer {
        makePlayer(source: try makeSource(frameCount: frameCount, size: size))
    }

    private func makeSource(frameCount: Int, size: CGSize = CGSize(width: 8, height: 8)) throws -> AnimatedImageSource {
        try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: frameCount, size: size)))
    }
}

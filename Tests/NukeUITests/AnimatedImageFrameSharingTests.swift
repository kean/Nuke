// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

/// What every player of one animation shares: the decoded frames, the decoder
/// that produces them, and the share of the pool they are held in.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageFrameSharingTests {
    /// The frames of the animations these tests build: 32×32, four bytes a
    /// pixel. Every limit below is written as a number of them.
    static let bytesPerFrame = 32 * 32 * 4

    /// A pool of its own for every test: what a player is allowed to hold
    /// depends on what every other animation on screen is asking for, and the
    /// suite runs beside every other one.
    private let pool = AnimatedImageFramePool()

    // MARK: Sharing the Frames

    @Test func aSecondPlayerFindsTheFramesTheFirstDecoded() async throws {
        let source = try makeSource(frameCount: 6)
        let first = makeBuffer(source: source)
        first.setCurrentIndex(0)
        await first.waitUntilFull()

        let second = makeBuffer(source: source)

        // Nothing left to do: every frame it wants is already in memory.
        #expect(second.count == 6)
        #expect(second.isFull)
        #expect(second.decodedFrameCount == 0)
        #expect(second.frame(at: 3) === first.frame(at: 3))
    }

    @Test func aSharedFrameIsCountedOnce() async throws {
        let source = try makeSource(frameCount: 6)
        let first = makeBuffer(source: source)
        let second = makeBuffer(source: source)
        first.setCurrentIndex(0)
        await first.waitUntilFull()

        // Both players are drawing from all six frames...
        #expect(first.count == 6)
        #expect(second.count == 6)
        // ...and six frames is what they cost.
        #expect(pool.totalCost == first.byteCount)
        #expect(pool.animationCount == 1)
        #expect(pool.playerCount == 2)
    }

    @Test func aScreenOfOneAnimationCostsOneAnimation() throws {
        // The case the sharing exists for. Twenty copies of a sticker used to
        // ask for twenty windows, get a twentieth of the budget each, and
        // re-decode most of the animation on every loop – for one animation's
        // worth of distinct pixels.
        let pool = makePool(frames: 40)
        let source = try makeSource(frameCount: 30)

        let buffers = (0..<20).map { _ in makeBuffer(source: source, pool: pool) }

        #expect(buffers.allSatisfy { $0.capacity == 30 })
        #expect(pool.animationCount == 1)
    }

    @Test func twentyDifferentAnimationsStillDivideTheBudget() throws {
        // The other half of the same test: what is shared is one animation, not
        // the pool. Twenty different ones split it as they always did.
        let pool = makePool(frames: 40)

        let buffers = try (0..<20).map { _ in
            makeBuffer(source: try makeSource(frameCount: 30), pool: pool)
        }

        #expect(buffers.allSatisfy { $0.capacity == 2 })
        #expect(pool.animationCount == 20)
    }

    @Test func adifferentSizeIsADifferentSetOfFrames() throws {
        // A thumbnail and a full-screen view of one animation hold different
        // pixels, and there is nothing to share between them.
        let source = try makeSource(frameCount: 4, size: CGSize(width: 64, height: 64))
        var small = AnimatedImagePlayer.Options()
        small.maxPixelSize = 16

        _ = makeBuffer(source: source)
        _ = makeBuffer(source: source, options: small)

        #expect(pool.animationCount == 2)
    }

    @Test func aSizeTheAnimationIsAlreadyInsideOfSharesWithNoSizeAtAll() throws {
        // A view that worked out a limit larger than the animation downsamples
        // nothing, which is what a view that asked for no limit does too.
        let source = try makeSource(frameCount: 4, size: CGSize(width: 32, height: 32))
        var generous = AnimatedImagePlayer.Options()
        generous.maxPixelSize = 512

        _ = makeBuffer(source: source)
        _ = makeBuffer(source: source, options: generous)

        #expect(pool.animationCount == 1)
    }

    // MARK: Sharing the Decoder

    @Test func twoPlayersOnTheSameFrameDecodeItOnce() async throws {
        let source = try makeSource(frameCount: 4)
        let decoder = GatedFrameDecoder(source: source)
        let first = makeBuffer(source: source, decoder: decoder)
        let second = makeBuffer(source: source)
        #expect(first.store === second.store)

        for index in 0..<4 { await decoder.release(index) }
        await first.waitUntilFull()

        // Four frames, four decodes, two players: without the store this was
        // eight, and with twenty views on screen it was eighty.
        #expect(await decoder.decodeCount == 4)
        #expect(first.count == 4)
        #expect(second.count == 4)
    }

    @Test func aScreenOfOneAnimationIsDecodedOnce() async throws {
        // The whole point, measured: twenty views of one sticker used to be
        // twenty decoders walking the same container and decoding the same
        // frames, twenty times over on every loop.
        let source = try makeSource(frameCount: 12)
        let decoder = GatedFrameDecoder(source: source)
        let first = makeBuffer(source: source, decoder: decoder)
        let rest = (0..<19).map { _ in makeBuffer(source: source) }

        for index in 0..<12 { await decoder.release(index) }
        await first.waitUntilFull()

        // Twelve frames for twenty players, and one bitmap apiece rather than
        // twenty copies of it.
        #expect(await decoder.decodeCount == 12)
        #expect(rest.allSatisfy { $0.count == 12 })
        #expect(rest.allSatisfy { $0.frame(at: 0) === first.frame(at: 0) })
        #expect(pool.totalCost == first.byteCount)
    }

    @Test func aFrameIsOfferedToEveryPlayerWaitingForIt() async throws {
        let source = try makeSource(frameCount: 4)
        let decoder = GatedFrameDecoder(source: source)
        let first = makeBuffer(source: source, decoder: decoder)
        let second = makeBuffer(source: source)
        var reported: [Int] = []
        second.onFrame = { reported.append($0) }

        await decoder.release(0)
        let decode = try #require(first.store.currentDecode)
        await decode.value

        #expect(reported == [0])
    }

    // MARK: Playheads

    @Test func playheadsThatAgreeCostOneWindow() throws {
        let pool = makePool(frames: 8)
        let source = try makeSource(frameCount: 20)
        let first = makeBuffer(source: source, pool: pool)
        let second = makeBuffer(source: source, pool: pool)

        first.setCurrentIndex(4)
        second.setCurrentIndex(4)

        #expect(first.capacity == 8)
        #expect(second.capacity == 8)
    }

    @Test func playheadsThatScatterSplitTheWindow() throws {
        // Half the animation apart, so the two windows share nothing and each
        // one can only be half of what a single player would have had.
        let pool = makePool(frames: 8)
        let source = try makeSource(frameCount: 20)
        let first = makeBuffer(source: source, pool: pool)
        let second = makeBuffer(source: source, pool: pool)

        first.setCurrentIndex(0)
        second.setCurrentIndex(10)

        #expect(first.capacity == 4)
        #expect(second.capacity == 4)
    }

    @Test func playheadsThatDriftApartByOneKeepAlmostEverything() throws {
        // The windows still overlap almost exactly, so what the second player
        // costs is the one frame the first one isn't holding – not a second
        // window. Dividing by the number of playheads would have halved both.
        let pool = makePool(frames: 8)
        let source = try makeSource(frameCount: 20)
        let first = makeBuffer(source: source, pool: pool)
        let second = makeBuffer(source: source, pool: pool)

        first.setCurrentIndex(0)
        second.setCurrentIndex(1)

        #expect(first.capacity == 7)
        #expect(second.capacity == 7)
    }

    @Test func scatteredPlayheadsCostNothingWhenTheAnimationFits() throws {
        // Where they are only matters while the animation has to be windowed.
        let pool = makePool(frames: 100)
        let source = try makeSource(frameCount: 20)
        let first = makeBuffer(source: source, pool: pool)
        let second = makeBuffer(source: source, pool: pool)

        first.setCurrentIndex(0)
        second.setCurrentIndex(10)

        #expect(first.capacity == 20)
        #expect(second.capacity == 20)
    }

    @Test func aPlayerStartsWhereTheOthersAlreadyAre() async throws {
        let source = try makeSource(frameCount: 8, size: CGSize(width: 8, height: 8))
        let (first, clock) = makePlayer(source: source)
        await first.buffer.waitUntilFull()
        first.play()
        for _ in 0..<3 { clock.tick(0.1) }
        #expect(first.currentFrameIndex == 3)

        let (second, _) = makePlayer(source: source)

        #expect(second.currentFrameIndex == 3)
    }

    @Test func aPlayerCanBeToldToStartAtTheBeginning() async throws {
        let source = try makeSource(frameCount: 8, size: CGSize(width: 8, height: 8))
        let (first, clock) = makePlayer(source: source)
        await first.buffer.waitUntilFull()
        first.play()
        for _ in 0..<3 { clock.tick(0.1) }

        var options = AnimatedImagePlayer.Options()
        options.isSynchronizationEnabled = false
        let (second, _) = makePlayer(source: source, options: options)

        #expect(second.currentFrameIndex == 0)
    }

    @Test func aPlayerStartsAtTheBeginningWhenNothingElseIsPlaying() async throws {
        // A player that hasn't started is showing its first frame, not a
        // position worth falling in behind.
        let source = try makeSource(frameCount: 8, size: CGSize(width: 8, height: 8))
        let (first, _) = makePlayer(source: source)
        await first.buffer.waitUntilFull()

        let (second, _) = makePlayer(source: source)

        #expect(second.currentFrameIndex == 0)
    }

    // MARK: Outliving the Players

    @Test func theFramesOutliveThePlayerThatDecodedThem() async throws {
        // A cell that scrolls off and comes back used to re-decode the whole
        // animation. The frames stay until the pool needs the room.
        let source = try makeSource(frameCount: 6)
        var first: AnimatedImageFrameBuffer? = makeBuffer(source: source)
        first?.setCurrentIndex(0)
        await first?.waitUntilFull()
        let cost = pool.totalCost

        first = nil
        await settle()

        #expect(pool.playerCount == 0)
        #expect(pool.totalCost == cost) // Still there, waiting for a second look

        let second = makeBuffer(source: source)

        #expect(second.count == 6)
        #expect(second.decodedFrameCount == 0)
    }

    @Test func theFramesGoWhenTheAnimationDoes() async throws {
        var source: AnimatedImageSource? = try makeSource(frameCount: 6)
        var buffer: AnimatedImageFrameBuffer? = makeBuffer(source: try #require(source))
        buffer?.setCurrentIndex(0)
        await buffer?.waitUntilFull()
        #expect(pool.totalCost > 0)

        // Nothing refers to the animation any more – the pipeline's cache has
        // let it go – so the frames decoded from it are worth nothing.
        buffer = nil
        source = nil
        await settle()
        pool.rebalance()

        #expect(pool.animationCount == 0)
        #expect(pool.totalCost == 0)
    }

    @Test func theFramesNobodyIsPlayingAreTheFirstToGoBack() async throws {
        let pool = makePool(frames: 8)
        let kept = try makeSource(frameCount: 8)
        let dropped = try makeSource(frameCount: 8)
        var idle: AnimatedImageFrameBuffer? = makeBuffer(source: dropped, pool: pool)
        idle?.setCurrentIndex(0)
        await idle?.waitUntilFull()
        idle = nil
        await settle()

        // The pool is full of frames nobody is watching when a player arrives
        // that needs them.
        let playing = makeBuffer(source: kept, pool: pool)
        playing.setCurrentIndex(0)
        await playing.waitUntilFull()

        #expect(playing.count == 8)
        #expect(pool.totalCost <= pool.costLimit)
    }

    // MARK: Helpers

    private func makePool(frames: Int) -> AnimatedImageFramePool {
        AnimatedImageFramePool(costLimit: frames * Self.bytesPerFrame)
    }

    private func makeBuffer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        pool: AnimatedImageFramePool? = nil,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) -> AnimatedImageFrameBuffer {
        AnimatedImageFrameBuffer(source: source, options: options, pool: pool ?? self.pool, decoder: decoder)
    }

    private func makePlayer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options()
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let clock = ManualClock()
        return (AnimatedImagePlayer(source: source, options: options, clock: clock, pool: pool), clock)
    }

    private func makeSource(
        frameCount: Int,
        size: CGSize = CGSize(width: 32, height: 32)
    ) throws -> AnimatedImageSource {
        try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: frameCount, size: size)))
    }

    /// Waits for the division a released player asks for on the next turn of
    /// the main actor.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

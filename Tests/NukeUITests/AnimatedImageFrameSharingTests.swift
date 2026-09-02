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
        let first = makePlayer(source: source)
        await first.waitUntilFull()

        let second = makePlayer(source: source)

        // Nothing left to do: every frame it wants is already in memory.
        #expect(second.diagnostics.bufferedFrameCount == 6)
        #expect(second.diagnostics.decodedFrameCount == 0)
        #expect(second.store.frame(at: 3) === first.store.frame(at: 3))
    }

    @Test func aSharedFrameIsCountedOnce() async throws {
        let source = try makeSource(frameCount: 6)
        let first = makePlayer(source: source)
        let second = makePlayer(source: source)
        await first.waitUntilFull()

        // Both players are drawing from all six frames...
        #expect(first.diagnostics.bufferedFrameCount == 6)
        #expect(second.diagnostics.bufferedFrameCount == 6)
        // ...and six frames is what they cost.
        #expect(pool.totalCost == first.diagnostics.bufferedByteCount)
        #expect(pool.animationCount == 1)
        #expect(pool.playerCount == 2)
    }

    @Test func aScreenOfOneAnimationCostsOneAnimation() throws {
        // The case the sharing exists for: twenty copies of a sticker used to
        // get a twentieth of the budget each.
        let pool = makePool(frames: 40)
        let source = try makeSource(frameCount: 30)

        let players = (0..<20).map { _ in makePlayer(source: source, pool: pool) }

        #expect(players.allSatisfy { $0.diagnostics.bufferCapacity == 30 })
        #expect(pool.animationCount == 1)
    }

    @Test func twentyDifferentAnimationsStillDivideTheBudget() throws {
        // What is shared is one animation, not the pool.
        let pool = makePool(frames: 40)

        let players = try (0..<20).map { _ in
            makePlayer(source: try makeSource(frameCount: 30), pool: pool)
        }

        #expect(players.allSatisfy { $0.diagnostics.bufferCapacity == 2 })
        #expect(pool.animationCount == 20)
    }

    @Test func aSizeTheAnimationIsAlreadyInsideOfSharesWithNoSizeAtAll() throws {
        // A view that worked out a limit larger than the animation downsamples
        // nothing, which is what a view that asked for no limit does too.
        let source = try makeSource(frameCount: 4, size: CGSize(width: 32, height: 32))
        var generous = AnimatedImagePlayer.Options()
        generous.maxPixelSize = 512

        _ = makePlayer(source: source)
        _ = makePlayer(source: source, options: generous)

        #expect(pool.animationCount == 1)
    }

    // MARK: Sharing Across Sizes

    @Test func aSmallerViewDrawsFromTheFramesALargerOneDecoded() async throws {
        // A frame decoded for a larger view answers a smaller one, which
        // scales it as it draws it, so the sticker in a 300-point bubble and
        // the same sticker in a 44-point avatar are decoded once.
        let source = try makeSource(frameCount: 4, size: CGSize(width: 64, height: 64))
        let bubble = makePlayer(source: source)
        await bubble.waitUntilFull()

        var small = AnimatedImagePlayer.Options()
        small.maxPixelSize = 16
        let avatar = makePlayer(source: source, options: small)

        #expect(avatar.store === bubble.store)
        #expect(pool.animationCount == 1)
        #expect(avatar.diagnostics.decodedFrameCount == 0)
        #expect(avatar.diagnostics.bufferedFrameCount == 4)
    }

    @Test func theSmallerViewPaysTheLargerOnesBytes() async throws {
        // The trade: nothing is decoded twice, and the frames the avatar holds
        // are the bubble's – 64 pixels of them, not the 16 it asked for.
        let source = try makeSource(frameCount: 4, size: CGSize(width: 64, height: 64))
        let bubble = makePlayer(source: source)
        await bubble.waitUntilFull()

        var small = AnimatedImagePlayer.Options()
        small.maxPixelSize = 16
        let avatar = makePlayer(source: source, options: small)

        let frame = try #require(avatar.store.frame(at: 0))
        #expect(frame.width == 64)
        #expect(avatar.store.bytesPerFrame == bubble.store.bytesPerFrame)
    }

    @Test func aLargerViewDoesNotDrawFromASmallerOnesFrames() throws {
        // They would have to be scaled up, which is not a picture worth
        // showing, so the larger view decodes a set of its own – and the set
        // the smaller view is playing from stays where it is.
        let source = try makeSource(frameCount: 4, size: CGSize(width: 64, height: 64))
        var small = AnimatedImagePlayer.Options()
        small.maxPixelSize = 16
        let avatar = makePlayer(source: source, options: small)

        let bubble = makePlayer(source: source)

        #expect(bubble.store !== avatar.store)
        #expect(pool.animationCount == 2)
    }

    @Test func aViewTakesTheSmallestFramesThatCoverIt() throws {
        // Two sets already exist, and the cheapest one that answers is the one
        // it joins: a view never pays for more pixels than it has to.
        let source = try makeSource(frameCount: 4, size: CGSize(width: 64, height: 64))
        var medium = AnimatedImagePlayer.Options()
        medium.maxPixelSize = 32
        var large = AnimatedImagePlayer.Options()
        large.maxPixelSize = 48
        let mediumView = makePlayer(source: source, options: medium)
        let largeView = makePlayer(source: source, options: large)
        #expect(pool.animationCount == 2)

        var small = AnimatedImagePlayer.Options()
        small.maxPixelSize = 16
        let smallView = makePlayer(source: source, options: small)

        #expect(smallView.store === mediumView.store)
        #expect(smallView.store !== largeView.store)
        #expect(pool.animationCount == 2)
    }

    @Test func aViewDoesNotDrawFromLargerFramesDrawnDifferently() throws {
        // Size is not the only thing that has to cover: two views drawing the
        // animation differently must not be handed each other's frames,
        // whatever size they are.
        let source = try makeSource(frameCount: 4, size: CGSize(width: 64, height: 64))
        var tinted = AnimatedImagePlayer.Options()
        tinted.frameTransform = AnimatedImageFrameTransform(identifier: "tint") { $0 }
        _ = makePlayer(source: source, options: tinted)

        var small = AnimatedImagePlayer.Options()
        small.maxPixelSize = 16
        _ = makePlayer(source: source, options: small)

        #expect(pool.animationCount == 2)
    }

    @Test func theFramesOfALargerViewThatHasGoneAnswerASmallerOne() async throws {
        // The frames outlive the player that decoded them, and a view that
        // wants fewer pixels than they hold still finds them.
        let source = try makeSource(frameCount: 4, size: CGSize(width: 64, height: 64))
        var bubble: AnimatedImagePlayer? = makePlayer(source: source)
        await bubble?.waitUntilFull()
        bubble = nil
        await settle()

        var small = AnimatedImagePlayer.Options()
        small.maxPixelSize = 16
        let avatar = makePlayer(source: source, options: small)

        #expect(avatar.diagnostics.bufferedFrameCount == 4)
        #expect(avatar.diagnostics.decodedFrameCount == 0)
        #expect(pool.animationCount == 1)
    }

    // MARK: Sharing the Decoder

    @Test func twoPlayersOnTheSameFrameDecodeItOnce() async throws {
        let source = try makeSource(frameCount: 4)
        let decoder = GatedFrameDecoder(source: source)
        let first = makePlayer(source: source, decoder: decoder)
        let second = makePlayer(source: source)
        #expect(first.store === second.store)

        for index in 0..<4 { await decoder.release(index) }
        await first.waitUntilFull()

        // Four frames, four decodes, two players.
        #expect(await decoder.decodeCount == 4)
        #expect(first.diagnostics.bufferedFrameCount == 4)
        #expect(second.diagnostics.bufferedFrameCount == 4)
    }

    @Test func aScreenOfOneAnimationIsDecodedOnce() async throws {
        let source = try makeSource(frameCount: 12)
        let decoder = GatedFrameDecoder(source: source)
        let first = makePlayer(source: source, decoder: decoder)
        let rest = (0..<19).map { _ in makePlayer(source: source) }

        for index in 0..<12 { await decoder.release(index) }
        await first.waitUntilFull()

        // Twelve decodes for twenty players, and one bitmap apiece.
        #expect(await decoder.decodeCount == 12)
        #expect(rest.allSatisfy { $0.diagnostics.bufferedFrameCount == 12 })
        #expect(rest.allSatisfy { $0.store.frame(at: 0) === first.store.frame(at: 0) })
        #expect(pool.totalCost == first.diagnostics.bufferedByteCount)
    }

    @Test func aFrameIsOfferedToEveryPlayerWaitingForIt() async throws {
        let source = try makeSource(frameCount: 4)
        let decoder = GatedFrameDecoder(source: source)
        let first = makePlayer(source: source, decoder: decoder)
        let second = makePlayer(source: source)
        var reported = 0
        second.onFrame = { _ in reported += 1 }

        await decoder.release(0)
        let decode = try #require(first.store.currentDecode)
        await decode.value

        // The player that didn't schedule the decode is handed the frame too.
        #expect(reported == 1)
        #expect(second.image != nil)
    }

    @Test func theFramesAreDecodedInPlaybackOrder() async throws {
        // What makes the first frames appear first, rather than the animation
        // waiting on a window filled in whatever order the players joined.
        let source = try makeSource(frameCount: 4)
        let decoder = GatedFrameDecoder(source: source)
        let player = makePlayer(source: source, decoder: decoder)

        for index in 0..<4 { await decoder.release(index) }
        await player.waitUntilFull()

        #expect(await decoder.startedIndexes == [0, 1, 2, 3])
    }

    // MARK: Playheads

    @Test func playheadsThatAgreeCostOneWindow() throws {
        // Four frames of pool for an animation of twenty: one window of the
        // read-ahead, whichever of the two players is asked.
        let pool = makePool(frames: 4)
        let source = try makeSource(frameCount: 20)
        let first = makePlayer(source: source, pool: pool)
        let second = makePlayer(source: source, pool: pool)

        first.seek(toFrame: 4)
        second.seek(toFrame: 4)

        #expect(first.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
        #expect(second.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func playheadsThatScatterSplitTheWindow() throws {
        // Half the animation apart, so the two windows share nothing and the
        // four frames are two each – short of the read-ahead a player alone
        // would keep.
        let pool = makePool(frames: 4)
        let source = try makeSource(frameCount: 20)
        let first = makePlayer(source: source, pool: pool)
        let second = makePlayer(source: source, pool: pool)

        first.seek(toFrame: 0)
        second.seek(toFrame: 10)

        #expect(first.diagnostics.bufferCapacity == 2)
        #expect(second.diagnostics.bufferCapacity == 2)
    }

    @Test func playheadsThatDriftApartByOneKeepAlmostEverything() throws {
        // The windows still overlap almost exactly, so what the second player
        // costs is the one frame the first one isn't holding – not a second
        // window. Dividing by the number of playheads would have left two each.
        let pool = makePool(frames: 4)
        let source = try makeSource(frameCount: 20)
        let first = makePlayer(source: source, pool: pool)
        let second = makePlayer(source: source, pool: pool)

        first.seek(toFrame: 0)
        second.seek(toFrame: 1)

        #expect(first.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
        #expect(second.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func scatteredPlayheadsCostNothingWhenTheAnimationFits() throws {
        // Where they are only matters while the animation has to be windowed.
        let pool = makePool(frames: 100)
        let source = try makeSource(frameCount: 20)
        let first = makePlayer(source: source, pool: pool)
        let second = makePlayer(source: source, pool: pool)

        first.seek(toFrame: 0)
        second.seek(toFrame: 10)

        #expect(first.diagnostics.bufferCapacity == 20)
        #expect(second.diagnostics.bufferCapacity == 20)
    }

    @Test func aPlayerStartsWhereTheOthersAlreadyAre() async throws {
        let source = try makeSource(frameCount: 8, size: CGSize(width: 8, height: 8))
        let (first, clock) = makeIdlePlayer(source: source)
        await first.waitUntilFull()
        first.play()
        await first.waitUntilFull()
        for _ in 0..<3 { clock.tick(0.1) }
        #expect(first.currentFrameIndex == 3)

        let (second, _) = makeIdlePlayer(source: source)

        #expect(second.currentFrameIndex == 3)
    }

    @Test func aPlayerCanBeToldToStartAtTheBeginning() async throws {
        let source = try makeSource(frameCount: 8, size: CGSize(width: 8, height: 8))
        let (first, clock) = makeIdlePlayer(source: source)
        await first.waitUntilFull()
        first.play()
        await first.waitUntilFull()
        for _ in 0..<3 { clock.tick(0.1) }

        var options = AnimatedImagePlayer.Options()
        options.isSynchronizationEnabled = false
        let (second, _) = makeIdlePlayer(source: source, options: options)

        #expect(second.currentFrameIndex == 0)
    }

    @Test func aPlayerStartsAtTheBeginningWhenNothingElseIsPlaying() async throws {
        // A player that hasn't started is showing its first frame, not a
        // position worth falling in behind.
        let source = try makeSource(frameCount: 8, size: CGSize(width: 8, height: 8))
        let (first, _) = makeIdlePlayer(source: source)
        await first.waitUntilFull()

        let (second, _) = makeIdlePlayer(source: source)

        #expect(second.currentFrameIndex == 0)
    }

    // MARK: Outliving the Players

    @Test func theFramesOutliveThePlayerThatDecodedThem() async throws {
        // A cell that scrolls off and comes back used to re-decode the whole
        // animation. The frames stay until the pool needs the room.
        let source = try makeSource(frameCount: 6)
        var first: AnimatedImagePlayer? = makePlayer(source: source)
        await first?.waitUntilFull()
        let cost = pool.totalCost

        first = nil
        await settle()

        #expect(pool.playerCount == 0)
        #expect(pool.totalCost == cost) // Still there, waiting for a second look

        let second = makePlayer(source: source)

        #expect(second.diagnostics.bufferedFrameCount == 6)
        #expect(second.diagnostics.decodedFrameCount == 0)
    }

    @Test func theFramesGoWhenTheAnimationDoes() async throws {
        var source: AnimatedImageSource? = try makeSource(frameCount: 6)
        var player: AnimatedImagePlayer? = makePlayer(source: try #require(source))
        await player?.waitUntilFull()
        #expect(pool.totalCost > 0)

        // Nothing refers to the animation any more – the pipeline's cache has
        // let it go – so the frames decoded from it are worth nothing.
        player = nil
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
        var idle: AnimatedImagePlayer? = makePlayer(source: dropped, pool: pool)
        await idle?.waitUntilFull()
        idle = nil
        await settle()

        // The pool is full of frames nobody is watching when a player arrives
        // that needs them.
        let playing = makePlayer(source: kept, pool: pool)
        await playing.waitUntilFull()

        #expect(playing.diagnostics.bufferedFrameCount == 8)
        #expect(pool.totalCost <= pool.costLimit)
    }

    // MARK: Helpers

    private func makePool(frames: Int) -> AnimatedImageFramePool {
        AnimatedImageFramePool(costLimit: frames * Self.bytesPerFrame)
    }

    /// A player that is playing, which is what makes it ask for a full window
    /// of frames. One that isn't asks for two.
    private func makePlayer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        pool: AnimatedImageFramePool? = nil,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) -> AnimatedImagePlayer {
        let player = makeIdlePlayer(source: source, options: options, pool: pool, decoder: decoder).player
        player.play()
        return player
    }

    /// A player nothing has started, on a clock the test drives.
    private func makeIdlePlayer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        pool: AnimatedImageFramePool? = nil,
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let clock = ManualClock()
        let player = AnimatedImagePlayer(
            source: source,
            options: options,
            clock: clock,
            pool: pool ?? self.pool,
            decoder: decoder
        )
        return (player, clock)
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

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageFramePoolTests {
    /// The frames of the animations these tests build: 32×32, four bytes a
    /// pixel. Every limit below is written as a number of them.
    static let bytesPerFrame = 32 * 32 * 4

    // MARK: Dividing the Budget

    @Test func givesAPlayerWhatItAsksForWhileThereIsEnough() throws {
        let pool = makePool(frames: 100)

        let player = try makePlayer(frameCount: 20, pool: pool)

        #expect(player.diagnostics.bufferCapacity == 20)
    }

    @Test func aShareShortOfTheAnimationIsAWindowOfTheReadAhead() throws {
        // Five frames' worth of the pool each, and each holds the read-ahead
        // out of it: a window that slides re-decodes every frame each loop
        // however long it is, so the rest of the share would buy nothing.
        let pool = makePool(frames: 10)

        let first = try makePlayer(frameCount: 20, pool: pool)
        let second = try makePlayer(frameCount: 20, pool: pool)

        #expect(first.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
        #expect(second.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func shrinksTheAnimationsAlreadyPlayingWhenAnotherAppears() throws {
        let pool = makePool(frames: 24)
        let first = try makePlayer(frameCount: 20, pool: pool)
        #expect(first.diagnostics.bufferCapacity == 20)

        let second = try makePlayer(frameCount: 20, pool: pool)

        #expect(first.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
        #expect(second.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func givesTheSmallAnimationsWhatTheyNeedAndTheRestToTheLargeOne() throws {
        // An even split would hold the large animation to four frames and leave
        // half of what the small ones were given unused: they only have two
        // frames each to hold.
        let pool = makePool(frames: 12)

        let small = try makePlayer(frameCount: 2, pool: pool)
        let other = try makePlayer(frameCount: 2, pool: pool)
        let large = try makePlayer(frameCount: 8, pool: pool)

        #expect(small.diagnostics.bufferCapacity == 2)
        #expect(other.diagnostics.bufferCapacity == 2)
        #expect(large.diagnostics.bufferCapacity == 8)
    }

    @Test func neverHoldsFewerThanTwoFramesEachHoweverManyThereAre() throws {
        // Nothing to divide, and an animation still can't be played out of a
        // single frame: the total goes over the limit rather than stopping.
        let pool = makePool(frames: 1)

        let players = try (0..<4).map { _ in try makePlayer(frameCount: 20, pool: pool) }

        #expect(players.allSatisfy { $0.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount })
    }

    @Test func honorsThePlayersOwnBudgetWhenThePoolHasMoreToGive() throws {
        // The pool is the ceiling on every animation together; `maxBufferSize`
        // is still the ceiling on one of them.
        let pool = makePool(frames: 100)

        let player = try makePlayer(frameCount: 40, maxBufferSize: 30 * Self.bytesPerFrame, pool: pool)

        #expect(player.diagnostics.isFullyBuffered == false)
        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func aPlayersBudgetIsAFifthOfThePoolByDefault() throws {
        // Large enough that what browsers keep whole fits, small enough that no
        // one animation can take the pool.
        let pool = makePool(frames: 100)
        #expect(pool.defaultMaxBufferSize == 20 * Self.bytesPerFrame)

        let fits = try makePlayer(frameCount: 20, maxBufferSize: nil, pool: pool)
        let doesNot = try makePlayer(frameCount: 21, maxBufferSize: nil, pool: pool)

        #expect(fits.diagnostics.isFullyBuffered)
        #expect(doesNot.diagnostics.isFullyBuffered == false)
    }

    @Test func theDefaultBudgetFollowsTheLimit() throws {
        let pool = makePool(frames: 100)
        let player = try makePlayer(frameCount: 40, maxBufferSize: nil, pool: pool)
        #expect(player.diagnostics.isFullyBuffered == false)

        pool.costLimit = 200 * Self.bytesPerFrame

        #expect(player.diagnostics.isFullyBuffered)
        #expect(player.diagnostics.bufferCapacity == 40)
    }

    @Test func measuresAnAnimationByWhatItCostsDecodedNotByWhatItWeighs() throws {
        // The frames are solid colors, so the file is smaller than a single
        // decoded frame; the budget has to see through that.
        let pool = makePool(frames: 100) // A default budget of twenty 32×32 frames
        let source = try makeSource(frameCount: 10, size: CGSize(width: 64, height: 64)) // Forty of them
        #expect(source.data.count < source.bytesPerFrame)

        let player = try makePlayer(source: source, maxBufferSize: nil, pool: pool)

        #expect(player.diagnostics.isFullyBuffered == false)
    }

    // MARK: Reacting to the Screen

    @Test func aPlayerNobodyIsWatchingLeavesItsShareToTheRest() throws {
        let pool = makePool(frames: 24)
        let playing = try makePlayer(frameCount: 20, pool: pool)
        let offscreen = try makePlayer(frameCount: 20, pool: pool)
        #expect(playing.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)

        // What `AnimatedImageView` does when it scrolls out of a window.
        offscreen.keepsFullBuffer = false

        #expect(offscreen.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount)
        #expect(playing.diagnostics.bufferCapacity == 20)
    }

    @Test func givesTheShareBackWhenAPlayerIsReleased() async throws {
        let pool = makePool(frames: 24)
        let survivor = try makePlayer(frameCount: 20, pool: pool)
        var released: AnimatedImagePlayer? = try makePlayer(frameCount: 20, pool: pool)
        #expect(released != nil)
        #expect(survivor.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)

        released = nil

        // A `deinit` isn't on the main actor, so the pool is asked to divide
        // the budget again on the next turn rather than on the spot.
        for _ in 0..<100 where survivor.diagnostics.bufferCapacity != 20 {
            await Task.yield()
        }
        #expect(survivor.diagnostics.bufferCapacity == 20)
        #expect(pool.playerCount == 1)
    }

    @Test func changingTheLimitResizesTheWindows() throws {
        let pool = makePool(frames: 4)
        let player = try makePlayer(frameCount: 20, pool: pool)
        #expect(player.diagnostics.bufferCapacity == 4)

        pool.costLimit = 20 * Self.bytesPerFrame
        #expect(player.diagnostics.bufferCapacity == 20)

        pool.costLimit = 8 * Self.bytesPerFrame
        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func lowerLimitDropsTheFramesThatNoLongerFit() async throws {
        let pool = makePool(frames: 8)
        let player = try makePlayer(frameCount: 8, pool: pool)
        await player.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 8)

        pool.costLimit = 3 * Self.bytesPerFrame

        #expect(player.diagnostics.bufferedFrameCount == 3)
        #expect(pool.totalCost <= pool.costLimit)
    }

    @Test func aMemoryWarningHoldsEveryAnimationAtTheFloor() throws {
        // One warning, one answer: the pool is what divides the budget, so it
        // is what gives it back rather than every player separately.
        let pool = makePool(frames: 12)
        let first = try makePlayer(frameCount: 20, pool: pool)
        let second = try makePlayer(frameCount: 20, pool: pool)
        #expect(first.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)

        pool.reduceMemoryUsage()

        #expect(first.diagnostics.bufferCapacity == 2)
        #expect(second.diagnostics.bufferCapacity == 2)
    }

    @Test func givesTheBudgetBackOnceTheMemoryPressureHasPassed() async throws {
        // A window shrunk by one memory warning would otherwise stay shrunk
        // for the life of the player, re-decoding every frame of every loop.
        let pool = makePool(frames: 24)
        pool.memoryPressureGracePeriod = 0.01
        let player = try makePlayer(frameCount: 20, pool: pool)

        pool.reduceMemoryUsage()
        #expect(player.diagnostics.bufferCapacity == 2)

        for _ in 0..<200 where player.diagnostics.bufferCapacity == 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(player.diagnostics.bufferCapacity == 20)
    }

    // MARK: Diagnostics

    @Test func reportsWhatThePlayersAreHolding() async throws {
        let pool = makePool(frames: 100)
        let first = try makePlayer(frameCount: 4, pool: pool)
        let second = try makePlayer(frameCount: 4, pool: pool)
        await first.waitUntilFull()
        await second.waitUntilFull()

        #expect(pool.playerCount == 2)
        #expect(pool.activePlayerCount == 2)
        #expect(pool.totalCost == first.diagnostics.bufferedByteCount + second.diagnostics.bufferedByteCount)
        #expect(pool.totalCost > 0)

        second.keepsFullBuffer = false

        #expect(pool.playerCount == 2)
        #expect(pool.activePlayerCount == 1)
    }

    @Test func theSharedPoolIsWhatAPlayerDrawsFromByDefault() throws {
        let source = try makeSource(frameCount: 4)
        let count = AnimatedImageFramePool.shared.playerCount

        let player = AnimatedImagePlayer(source: source)

        #expect(AnimatedImageFramePool.shared.playerCount == count + 1)
        #expect(player.diagnostics.bufferByteLimit > 0)
    }

    // MARK: Helpers

    private func makePool(frames: Int) -> AnimatedImageFramePool {
        AnimatedImageFramePool(costLimit: frames * Self.bytesPerFrame)
    }

    /// A player that is playing, which is what makes it ask for a full window
    /// of frames. One that isn't asks for two.
    ///
    /// The budget is spelled out because the default is a share of the pool
    /// itself, and what these tests divide is the pool.
    private func makePlayer(
        frameCount: Int,
        maxBufferSize: Int? = 10 * 1_048_576,
        pool: AnimatedImageFramePool
    ) throws -> AnimatedImagePlayer {
        try makePlayer(source: try makeSource(frameCount: frameCount), maxBufferSize: maxBufferSize, pool: pool)
    }

    private func makePlayer(
        source: AnimatedImageSource,
        maxBufferSize: Int? = 10 * 1_048_576,
        pool: AnimatedImageFramePool
    ) throws -> AnimatedImagePlayer {
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = maxBufferSize
        let player = AnimatedImagePlayer(source: source, options: options, clock: ManualClock(), pool: pool)
        player.play()
        return player
    }

    private func makeSource(frameCount: Int, size: CGSize = CGSize(width: 32, height: 32)) throws -> AnimatedImageSource {
        try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: frameCount, size: size)))
    }
}

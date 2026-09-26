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
    static let frameSize = CGSize(width: 32, height: 32)

    // MARK: Dividing the Budget

    @Test func givesAPlayerWhatItAsksForWhileThereIsEnough() throws {
        let pool = makePool(frames: 100)

        let player = makePlayer(frameCount: 20, pool: pool)

        #expect(player.diagnostics.bufferCapacity == 20)
    }

    @Test func anAnimationAloneMayTakeTheWholePool() throws {
        // There is nobody to save the rest for.
        let pool = makePool(frames: 100)

        let player = makePlayer(frameCount: 100, pool: pool)

        #expect(player.diagnostics.isFullyBuffered)
        #expect(player.diagnostics.bufferCapacity == 100)
    }

    @Test func anAnimationLargerThanThePoolKeepsTheReadAhead() throws {
        let pool = makePool(frames: 100)

        let player = makePlayer(frameCount: 101, pool: pool)

        #expect(player.diagnostics.isFullyBuffered == false)
        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func keepsTheReadAheadWhenNoAnimationFits() throws {
        // Ten frames of pool for two animations of twenty: neither fits, so
        // each holds a window of the read-ahead, and the four frames left over
        // buy nothing – a window that slides re-decodes every frame each loop
        // however long it is.
        let pool = makePool(frames: 10)

        let first = makePlayer(frameCount: 20, pool: pool)
        let second = makePlayer(frameCount: 20, pool: pool)

        #expect(first.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
        #expect(second.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func holdsAsManyAnimationsWholeAsFitSmallestFirst() throws {
        // Thirty frames of pool for fifty frames of animation. An even split –
        // seven or eight frames each – would hold nothing whole. Smallest
        // first, two of the four are whole, and the other two play out of a
        // window of the read-ahead.
        let pool = makePool(frames: 30)
        let window = AnimatedImagePlayer.readAheadFrameCount + 1

        let players = [12, 10, 8, 20].map { makePlayer(frameCount: $0, pool: pool) }

        #expect(players.map(\.diagnostics.bufferCapacity) == [window, 10, 8, window])
    }

    @Test func aSmallerNewcomerTakesThePlaceOfALargerAnimation() throws {
        // Twenty-two frames of pool. The animation of twenty had it to
        // itself; the one of sixteen fits beside the twenty's read-ahead where
        // the twenty wouldn't fit beside the sixteen's, so the twenty is the
        // one that gives way.
        let pool = makePool(frames: 22)
        let large = makePlayer(frameCount: 20, pool: pool)
        #expect(large.diagnostics.bufferCapacity == 20)

        let small = makePlayer(frameCount: 16, pool: pool)

        #expect(small.diagnostics.bufferCapacity == 16)
        #expect(large.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func aNewcomerTheSameSizeWaitsForTheOneAlreadyWhole() throws {
        // Twenty-four frames of pool for two animations of twenty: room for one
        // whole beside the other's read-ahead. The one already whole keeps its
        // frames rather than dropping them to decode the other's.
        let pool = makePool(frames: 24)
        let first = makePlayer(frameCount: 20, pool: pool)
        #expect(first.diagnostics.bufferCapacity == 20)

        let second = makePlayer(frameCount: 20, pool: pool)

        #expect(first.diagnostics.bufferCapacity == 20)
        #expect(second.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func givesTheSmallAnimationsWhatTheyNeedAndTheRestToTheLargeOne() throws {
        // An even split would hold the large animation to four frames and leave
        // half of what the small ones were given unused: they only have two
        // frames each to hold.
        let pool = makePool(frames: 12)

        let small = makePlayer(frameCount: 2, pool: pool)
        let other = makePlayer(frameCount: 2, pool: pool)
        let large = makePlayer(frameCount: 8, pool: pool)

        #expect(small.diagnostics.bufferCapacity == 2)
        #expect(other.diagnostics.bufferCapacity == 2)
        #expect(large.diagnostics.bufferCapacity == 8)
    }

    @Test func neverHoldsFewerThanTwoFramesEachHoweverManyThereAre() throws {
        // Nothing to divide, and an animation still can't be played out of a
        // single frame: the total goes over the limit rather than stopping.
        let pool = makePool(frames: 1)

        let players = (0..<4).map { _ in makePlayer(frameCount: 20, pool: pool) }

        #expect(players.allSatisfy { $0.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount })
    }

    @Test func honorsThePlayersOwnBudgetWhenThePoolHasMoreToGive() throws {
        // The pool is the ceiling on every animation together; `maxBufferSize`
        // is still the ceiling on one of them.
        let pool = makePool(frames: 100)

        let player = makePlayer(frameCount: 40, maxBufferSize: 30 * Self.bytesPerFrame, pool: pool)

        #expect(player.diagnostics.isFullyBuffered == false)
        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func measuresAnAnimationByWhatItCostsDecodedNotByWhatItWeighs() throws {
        // The frames are solid colors, so the file is smaller than a single
        // decoded frame; the pool has to see through that.
        let pool = makePool(frames: 100) // Twenty-five frames of 64×64
        let source = Test.animatedGIFSource(frameCount: 30, size: CGSize(width: 64, height: 64))
        #expect(source.data.count < source.bytesPerFrame)

        let player = makePlayer(source: source, pool: pool)

        #expect(player.diagnostics.isFullyBuffered == false)
    }

    // MARK: Reacting to the Screen

    @Test func aPlayerNobodyIsWatchingLeavesItsShareToTheRest() throws {
        let pool = makePool(frames: 24)
        let playing = makePlayer(frameCount: 20, pool: pool)
        let offscreen = makePlayer(frameCount: 16, pool: pool)
        #expect(playing.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)

        // What `AnimatedImageView` does when it scrolls out of a window.
        offscreen.keepsFullBuffer = false

        #expect(offscreen.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount)
        #expect(playing.diagnostics.bufferCapacity == 20)
    }

    @Test func dividesTheBudgetOnceForAScreenfulOfReleasedPlayers() async throws {
        let pool = makePool(frames: 100)
        var players: [AnimatedImagePlayer] = []
        for _ in 0..<8 {
            let player = makePlayer(frameCount: 4, pool: pool)
            await player.waitUntilFull()
            players.append(player)
        }
        let divisions = pool.rebalanceCount

        players.removeAll()
        await drainPendingWork()

        // A list scrolling releases a screenful of players in one turn, and
        // every division walks every animation in the pool.
        #expect(pool.rebalanceCount == divisions + 1)
        #expect(pool.animationCount == 0)
    }

    @Test func givesTheShareBackWhenAPlayerIsReleased() async throws {
        let pool = makePool(frames: 24)
        let survivor = makePlayer(frameCount: 20, pool: pool)
        var released: AnimatedImagePlayer? = makePlayer(frameCount: 16, pool: pool)
        #expect(released != nil)
        #expect(survivor.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)

        released = nil

        // A `deinit` isn't on the main actor, so the pool is asked to divide
        // the budget again on the next turn rather than on the spot.
        await waitUntil { survivor.diagnostics.bufferCapacity == 20 }
        #expect(survivor.diagnostics.bufferCapacity == 20)
        #expect(pool.playerCount == 1)
    }

    @Test func changingTheLimitResizesTheWindows() throws {
        let pool = makePool(frames: 4)
        let player = makePlayer(frameCount: 20, pool: pool)
        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)

        pool.costLimit = 20 * Self.bytesPerFrame
        #expect(player.diagnostics.bufferCapacity == 20)

        pool.costLimit = 8 * Self.bytesPerFrame
        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    @Test func lowerLimitDropsTheFramesThatNoLongerFit() async throws {
        let pool = makePool(frames: 8)
        let player = makePlayer(frameCount: 8, pool: pool)
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
        let first = makePlayer(frameCount: 20, pool: pool)
        let second = makePlayer(frameCount: 20, pool: pool)
        #expect(first.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)

        pool.reduceMemoryUsage()

        #expect(first.diagnostics.bufferCapacity == 2)
        #expect(second.diagnostics.bufferCapacity == 2)
    }

    @Test func aMemoryWarningGivesBackTheFramesNobodyIsPlaying() async throws {
        // A pool nearly full of animations a list has scrolled past would
        // otherwise answer a warning with the few frames its live windows hold.
        let pool = makePool(frames: 24)
        let scrolledPast = Test.animatedGIFSource(frameCount: 8, size: Self.frameSize)
        var released: AnimatedImagePlayer? = makePlayer(source: scrolledPast, pool: pool)
        await released?.waitUntilFull()
        released = nil
        await drainPendingWork()
        let playing = makePlayer(frameCount: 8, pool: pool)
        await playing.waitUntilFull()
        #expect(pool.animationCount == 2)
        #expect(pool.totalCost == 16 * Self.bytesPerFrame)

        pool.reduceMemoryUsage()

        // The animation nobody is playing goes whole, the one on screen down
        // to the floor.
        #expect(pool.animationCount == 1)
        #expect(pool.totalCost == AnimatedImagePlayer.idleFrameCount * Self.bytesPerFrame)
        #expect(playing.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount)
    }

    @Test func givesBackTheFramesNobodyIsPlayingWhenTheAppGoesToTheBackground() async throws {
        let pool = makePool(frames: 24)
        let scrolledPast = Test.animatedGIFSource(frameCount: 8, size: Self.frameSize)
        var released: AnimatedImagePlayer? = makePlayer(source: scrolledPast, pool: pool)
        await released?.waitUntilFull()
        released = nil
        await drainPendingWork()
        let paused = makePlayer(frameCount: 8, pool: pool)
        await paused.waitUntilFull()
        #expect(pool.animationCount == 2)

        pool.removeIdleAnimations()

        // Nothing is on screen, so the frames kept for a view that might come
        // back are a cache the app isn't using. The player that is still around
        // keeps what it is holding.
        #expect(pool.animationCount == 1)
        #expect(pool.totalCost == 8 * Self.bytesPerFrame)
    }

    @Test func givesBackTheFramesOfAnAnimationTheCacheHasLetGoOf() async throws {
        let pool = makePool(frames: 24)
        var source: AnimatedImageSource? = Test.animatedGIFSource(frameCount: 8, size: Self.frameSize)
        var player: AnimatedImagePlayer? = makePlayer(source: try #require(source), pool: pool)
        await player?.waitUntilFull()

        // The view goes, and then the cache lets go of the animation itself.
        player = nil
        source = nil
        await drainPendingWork()
        pool.removeIdleAnimations()

        #expect(pool.animationCount == 0)
        #expect(pool.totalCost == 0)
    }

    @Test func cachesNothingForAPlayerReleasedWhileTheMemoryPressureLasts() async throws {
        let pool = makePool(frames: 24)
        let source = Test.animatedGIFSource(frameCount: 8, size: Self.frameSize)
        var player: AnimatedImagePlayer? = makePlayer(source: source, pool: pool)
        await player?.waitUntilFull()

        pool.reduceMemoryUsage()
        // The list scrolls on while the pressure lasts. Keeping the frames it
        // leaves behind for a second look is what the warning ruled out.
        player = nil
        await drainPendingWork()

        #expect(pool.animationCount == 0)
        #expect(pool.totalCost == 0)
    }

    @Test func givesTheBudgetBackOnceTheMemoryPressureHasPassed() async throws {
        // A window shrunk by one memory warning would otherwise stay shrunk
        // for the life of the player, re-decoding every frame of every loop.
        let pool = makePool(frames: 24)
        pool.memoryPressureGracePeriod = 0.01
        let player = makePlayer(frameCount: 20, pool: pool)

        pool.reduceMemoryUsage()
        #expect(player.diagnostics.bufferCapacity == 2)

        await waitUntil { player.diagnostics.bufferCapacity != 2 }
        #expect(player.diagnostics.bufferCapacity == 20)
    }

    // MARK: Diagnostics

    @Test func reportsWhatThePlayersAreHolding() async throws {
        let pool = makePool(frames: 100)
        let first = makePlayer(frameCount: 4, pool: pool)
        let second = makePlayer(frameCount: 4, pool: pool)
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
        let source = Test.animatedGIFSource(frameCount: 4, size: Self.frameSize)
        let count = AnimatedImageFramePool.shared.playerCount

        let player = AnimatedImagePlayer(source: source)

        #expect(AnimatedImageFramePool.shared.playerCount == count + 1)
        #expect(player.diagnostics.bufferByteLimit > 0)
    }

    @Test func stopsCountingAPlayerTheMomentItIsReleased() throws {
        // Before the division its release asks for: a `deinit` can't divide
        // the budget, but the count is of the players still around.
        let pool = makePool(frames: 100)
        let kept = makePlayer(frameCount: 4, pool: pool)
        var released: AnimatedImagePlayer? = makePlayer(frameCount: 4, pool: pool)
        #expect(pool.playerCount == 2)
        #expect(pool.activePlayerCount == 2)

        released = nil

        #expect(released == nil)
        #expect(pool.playerCount == 1)
        #expect(pool.activePlayerCount == 1)
        #expect(pool.animationCount == 2) // Its frames are still kept
        #expect(kept.isPlaying)
    }

    // MARK: Limits

    @Test func theDefaultLimitIsAQuarterOfTheBudgetForDecodedImages() {
        // One figure split two ways: the image cache takes three quarters,
        // the frames of the animations the rest, capped at 128 MB.
        let limit = AnimatedImageFramePool.defaultCostLimit

        #expect(limit == min(ImageCache.defaultMemoryBudget / 4, 128 * 1_048_576))
        #expect(limit > 0)
        #expect(limit + ImageCache.defaultCostLimit <= ImageCache.defaultMemoryBudget)
        #expect(AnimatedImageFramePool().costLimit == limit)
    }

    @Test func settingTheLimitItAlreadyHasDividesNothing() throws {
        let pool = makePool(frames: 8)
        let player = makePlayer(frameCount: 4, pool: pool)
        let divisions = pool.rebalanceCount

        pool.costLimit = 8 * Self.bytesPerFrame
        #expect(pool.rebalanceCount == divisions)

        pool.costLimit = 9 * Self.bytesPerFrame
        #expect(pool.rebalanceCount == divisions + 1)
        #expect(player.diagnostics.bufferCapacity == 4)
    }

    @Test(arguments: [0, -1, Int.min])
    func aLimitOfNothingLeavesEveryAnimationItsTwoFrames(costLimit: Int) async throws {
        let pool = AnimatedImageFramePool(costLimit: costLimit)

        let player = makePlayer(frameCount: 8, pool: pool)
        await player.waitUntilFull()

        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount)
        #expect(player.diagnostics.bufferedFrameCount == AnimatedImagePlayer.idleFrameCount)
    }

    @Test func goesOverTheLimitRatherThanDropTheFramesPlaybackNeeds() async throws {
        // The one thing outside the limit: a player holds two frames however
        // little room there is. A pool over its limit never takes the frame
        // on screen or the one after it to get back under.
        let pool = makePool(frames: 1)
        let player = makePlayer(frameCount: 4, pool: pool)

        await player.waitUntilFull()

        #expect(player.isFrameBuffered(0))
        #expect(player.isFrameBuffered(1))
        #expect(pool.totalCost == 2 * Self.bytesPerFrame)
        #expect(pool.totalCost > pool.costLimit)
    }

    @Test func givesBackTheAnimationNobodyHasPlayedForLongestFirst() async throws {
        // Ten frames of pool, eight of them kept for two animations a list has
        // scrolled past. A third needs four, and the room comes out of the one
        // that went idle first; the other is still there for a second look.
        let pool = makePool(frames: 10)
        // Held here the way the image cache holds them: the frames of an
        // animation nothing refers to go with it.
        let sources = (0..<2).map { _ in Test.animatedGIFSource(frameCount: 4, size: Self.frameSize) }
        var older: AnimatedImagePlayer? = makePlayer(source: sources[0], pool: pool)
        var newer: AnimatedImagePlayer? = makePlayer(source: sources[1], pool: pool)
        await older?.waitUntilFull()
        await newer?.waitUntilFull()
        let olderFrames = try #require(older?.store)
        let newerFrames = try #require(newer?.store)
        older = nil
        await drainPendingWork()
        newer = nil
        await drainPendingWork()
        #expect(pool.playerCount == 0)
        #expect(pool.totalCost == 8 * Self.bytesPerFrame)

        let playing = makePlayer(frameCount: 4, pool: pool)
        await playing.waitUntilFull()

        #expect(olderFrames.byteCount == 0)
        #expect(newerFrames.byteCount == 4 * Self.bytesPerFrame)
        #expect(playing.diagnostics.bufferedFrameCount == 4)
        #expect(pool.animationCount == 2)
        #expect(pool.totalCost <= pool.costLimit)
    }

    // MARK: Helpers

    private func makePool(frames: Int) -> AnimatedImageFramePool {
        AnimatedImageFramePool(costLimit: frames * Self.bytesPerFrame)
    }

    /// A player that is playing, which is what makes it ask for a full window
    /// of frames. One that isn't asks for two.
    private func makePlayer(
        frameCount: Int,
        maxBufferSize: Int? = nil,
        pool: AnimatedImageFramePool
    ) -> AnimatedImagePlayer {
        makePlayer(source: Test.animatedGIFSource(frameCount: frameCount, size: Self.frameSize), maxBufferSize: maxBufferSize, pool: pool)
    }

    private func makePlayer(
        source: AnimatedImageSource,
        maxBufferSize: Int? = nil,
        pool: AnimatedImageFramePool
    ) -> AnimatedImagePlayer {
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = maxBufferSize
        let player = AnimatedImageTest.makePlayer(source: source, options: options, pool: pool).player
        player.play()
        return player
    }
}

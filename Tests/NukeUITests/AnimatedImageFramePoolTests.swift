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

        let buffer = try makeBuffer(frameCount: 20, pool: pool)

        #expect(buffer.capacity == 20)
    }

    @Test func dividesTheBudgetBetweenThePlayersThatDoNotFit() throws {
        let pool = makePool(frames: 10)

        let first = try makeBuffer(frameCount: 20, pool: pool)
        let second = try makeBuffer(frameCount: 20, pool: pool)

        #expect(first.capacity == 5)
        #expect(second.capacity == 5)
    }

    @Test func shrinksTheAnimationsAlreadyPlayingWhenAnotherAppears() throws {
        let pool = makePool(frames: 12)
        let first = try makeBuffer(frameCount: 20, pool: pool)
        #expect(first.capacity == 12)

        let second = try makeBuffer(frameCount: 20, pool: pool)

        #expect(first.capacity == 6)
        #expect(second.capacity == 6)
    }

    @Test func givesTheSmallAnimationsWhatTheyNeedAndTheRestToTheLargeOne() throws {
        // An even split would hold the large animation to five frames and leave
        // three quarters of what the small ones were given unused: they only
        // have two frames each to hold.
        let pool = makePool(frames: 12)

        let small = try makeBuffer(frameCount: 2, pool: pool)
        let other = try makeBuffer(frameCount: 2, pool: pool)
        let large = try makeBuffer(frameCount: 40, pool: pool)

        #expect(small.capacity == 2)
        #expect(other.capacity == 2)
        #expect(large.capacity == 8)
    }

    @Test func neverHoldsFewerThanTwoFramesEachHoweverManyThereAre() throws {
        // Nothing to divide, and an animation still can't be played out of a
        // single frame: the total goes over the limit rather than stopping.
        let pool = makePool(frames: 1)

        let buffers = try (0..<4).map { _ in try makeBuffer(frameCount: 20, pool: pool) }

        #expect(buffers.allSatisfy { $0.capacity == AnimatedImageFrameBuffer.idleCapacity })
    }

    @Test func honorsThePlayersOwnBudgetWhenThePoolHasMoreToGive() throws {
        // The pool is the ceiling on every animation together; `maxBufferSize`
        // is still the ceiling on one of them.
        let pool = makePool(frames: 100)

        let buffer = try makeBuffer(frameCount: 40, maxBufferSize: 6 * Self.bytesPerFrame, pool: pool)

        #expect(buffer.capacity == 6)
    }

    // MARK: Reacting to the Screen

    @Test func aPlayerNobodyIsWatchingLeavesItsShareToTheRest() throws {
        let pool = makePool(frames: 12)
        let playing = try makeBuffer(frameCount: 20, pool: pool)
        let offscreen = try makeBuffer(frameCount: 20, pool: pool)
        #expect(playing.capacity == 6)

        // What `AnimatedImageView` does when it scrolls out of a window.
        offscreen.fillsWindow = false

        #expect(offscreen.capacity == AnimatedImageFrameBuffer.idleCapacity)
        #expect(playing.capacity == 10)
    }

    @Test func givesTheShareBackWhenAPlayerIsReleased() async throws {
        let pool = makePool(frames: 12)
        let survivor = try makeBuffer(frameCount: 20, pool: pool)
        var released: AnimatedImageFrameBuffer? = try makeBuffer(frameCount: 20, pool: pool)
        #expect(released != nil)
        #expect(survivor.capacity == 6)

        released = nil

        // A `deinit` isn't on the main actor, so the pool is asked to divide
        // the budget again on the next turn rather than on the spot.
        for _ in 0..<100 where survivor.capacity != 12 {
            await Task.yield()
        }
        #expect(survivor.capacity == 12)
        #expect(pool.playerCount == 1)
    }

    @Test func changingTheLimitResizesTheWindows() throws {
        let pool = makePool(frames: 4)
        let buffer = try makeBuffer(frameCount: 20, pool: pool)
        #expect(buffer.capacity == 4)

        pool.costLimit = 16 * Self.bytesPerFrame
        #expect(buffer.capacity == 16)

        pool.costLimit = 8 * Self.bytesPerFrame
        #expect(buffer.capacity == 8)
    }

    @Test func lowerLimitDropsTheFramesThatNoLongerFit() async throws {
        let pool = makePool(frames: 8)
        let buffer = try makeBuffer(frameCount: 8, pool: pool)
        buffer.setCurrentIndex(0)
        await buffer.waitUntilFull()
        #expect(buffer.count == 8)

        pool.costLimit = 3 * Self.bytesPerFrame

        #expect(buffer.count == 3)
        #expect(pool.totalCost <= pool.costLimit)
    }

    @Test func aMemoryWarningHoldsEveryAnimationAtTheFloor() throws {
        // One warning, one answer: the pool is what divides the budget, so it
        // is what gives it back rather than every player separately.
        let pool = makePool(frames: 12)
        let first = try makeBuffer(frameCount: 20, pool: pool)
        let second = try makeBuffer(frameCount: 20, pool: pool)
        #expect(first.capacity == 6)

        pool.reduceMemoryUsage()

        #expect(first.capacity == 2)
        #expect(second.capacity == 2)
    }

    @Test func givesTheBudgetBackOnceTheMemoryPressureHasPassed() async throws {
        // A buffer shrunk by one memory warning would otherwise stay shrunk for
        // the life of the player, re-decoding every frame of every loop.
        let pool = makePool(frames: 12)
        pool.memoryPressureGracePeriod = 0.01
        let buffer = try makeBuffer(frameCount: 20, pool: pool)

        pool.reduceMemoryUsage()
        #expect(buffer.capacity == 2)

        for _ in 0..<200 where buffer.capacity == 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(buffer.capacity == 12)
    }

    // MARK: Diagnostics

    @Test func reportsWhatThePlayersAreHolding() async throws {
        let pool = makePool(frames: 100)
        let first = try makeBuffer(frameCount: 4, pool: pool)
        let second = try makeBuffer(frameCount: 4, pool: pool)
        first.setCurrentIndex(0)
        second.setCurrentIndex(0)
        await first.waitUntilFull()
        await second.waitUntilFull()

        #expect(pool.playerCount == 2)
        #expect(pool.activePlayerCount == 2)
        #expect(pool.totalCost == first.byteCount + second.byteCount)
        #expect(pool.totalCost > 0)

        second.fillsWindow = false

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

    private func makeBuffer(
        frameCount: Int,
        maxBufferSize: Int = 10 * 1_048_576,
        pool: AnimatedImageFramePool
    ) throws -> AnimatedImageFrameBuffer {
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = maxBufferSize
        return AnimatedImageFrameBuffer(source: try makeSource(frameCount: frameCount), options: options, pool: pool)
    }

    private func makeSource(frameCount: Int) throws -> AnimatedImageSource {
        let size = CGSize(width: 32, height: 32)
        return try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: frameCount, size: size)))
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

/// The set of decoded frames every player of one animation draws from: what
/// identifies it, what it charges the pool, and what it does with the frames
/// the decoder can't produce.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageFrameStoreDecodeTests {
    /// A pool of its own for every test: what a player is allowed to hold
    /// depends on what every other animation on screen is asking for, and the
    /// suite runs beside every other one.
    private let pool = AnimatedImageFramePool()

    // MARK: Keys

    @Test(arguments: [0, -16, CGFloat.infinity, CGFloat.nan])
    func aLimitThatDownsamplesNothingSharesTheFullSizeFrames(maxPixelSize: CGFloat) async throws {
        // None of these asks for fewer pixels than the animation has, so the
        // frames are the full-size ones – decoded at the animation's own size
        // rather than at a nonsense one, and shared with a player that asked
        // for no limit at all.
        let source = try makeSource(frameCount: 4)
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = maxPixelSize
        let odd = makePlayer(source: source, options: options)
        await odd.waitUntilFull()

        let plain = makePlayer(source: source)

        #expect(plain.store === odd.store)
        #expect(pool.animationCount == 1)
        #expect(odd.store.bytesPerFrame == source.bytesPerFrame)
        #expect(try #require(odd.store.frame(at: 0)).width == 32)
    }

    @Test func chargesADownsampledFrameWhatItCostsDecoded() async throws {
        // The pool divides the budget by what a frame will cost before any is
        // decoded – the canvas at four bytes a pixel, less the square of the
        // downsampling – and counts what the decoded ones actually occupy. The
        // two have to agree, or an animation the division held whole would
        // push the pool over its limit.
        let source = try makeSource(frameCount: 4, size: CGSize(width: 64, height: 32))
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 16
        let player = makePlayer(source: source, options: options)

        await player.waitUntilFull()

        #expect(player.store.bytesPerFrame == source.bytesPerFrame / 16)
        #expect(player.diagnostics.bufferedByteCount == 4 * player.store.bytesPerFrame)
        #expect(pool.totalCost == player.diagnostics.bufferedByteCount)
    }

    // MARK: Frames the Decoder Refuses

    @Test func settlesWhenTheDecoderRefusesAFrame() async throws {
        // A truncated animation: the container promises a frame the data
        // doesn't hold. The store stops expecting it rather than asking again.
        let source = try makeSource(frameCount: 4)
        let decoder = RefusingFrameDecoder(source: source, refusing: [2])
        let (player, _) = makeIdlePlayer(source: source, decoder: decoder)
        player.play()

        await waitForDecodes(of: player)

        #expect(player.store.currentDecode == nil) // Nothing left to try
        #expect(player.store.isPending(2) == false)
        #expect(player.isFrameBuffered(2) == false)
        #expect(player.diagnostics.bufferedFrameCount == 3)
        #expect(await decoder.requests == [0: 1, 1: 1, 2: 1, 3: 1])
    }

    @Test func holdsThePreviousFrameInPlaceOfOneTheDecoderRefuses() async throws {
        let source = try makeSource(frameCount: 4)
        let decoder = RefusingFrameDecoder(source: source, refusing: [2])
        let (player, clock) = makeIdlePlayer(source: source, decoder: decoder)
        player.play()
        await waitForDecodes(of: player)
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)
        let before = try #require(player.image)

        clock.tick(0.1)

        // The playhead moves on – waiting for a frame nobody is producing
        // would stop the animation for good – and the frame before it stays
        // on screen for the refused one's delay.
        #expect(player.currentFrameIndex == 2)
        #expect(player.image === before)

        clock.tick(0.1)

        #expect(player.currentFrameIndex == 3)
        #expect(player.image !== before)
    }

    @Test func doesNotAskForARefusedFrameAgainOnTheNextLoop() async throws {
        // A window that slides decodes every frame again on every loop. A
        // refused one is remembered instead: otherwise a truncated animation
        // would retry the frames it doesn't have on every pass.
        let source = try makeSource(frameCount: 4)
        let decoder = RefusingFrameDecoder(source: source, refusing: [2])
        let (player, clock) = makeIdlePlayer(source: source, options: .twoFrameBuffer, decoder: decoder)
        player.play()

        for _ in 0..<40 where player.completedLoopCount < 2 {
            await waitForDecodes(of: player)
            clock.tick(0.1)
        }

        #expect(player.completedLoopCount == 2)
        let requests = await decoder.requests
        #expect(requests[2] == 1)
        #expect(requests[0, default: 0] >= 2) // The window did slide
    }

    // MARK: The Decode in Flight

    @Test func aSeekDoesNotCancelTheDecodeAnotherPlayerIsWaitingFor() async throws {
        // Two copies of one animation on the same frame wait on one decode.
        // One of them seeking away leaves the other still waiting on it.
        let source = try makeSource(frameCount: 20)
        let decoder = GatedFrameDecoder(source: source)
        let (first, _) = makeIdlePlayer(source: source, decoder: decoder)
        first.play()
        let (second, _) = makeIdlePlayer(source: source)
        second.play()
        let decode = try #require(first.store.currentDecode)

        second.seek(toFrame: 10)

        #expect(first.store.currentDecode == decode)
        await decoder.release(0)
        await decode.value
        #expect(first.image != nil)
        #expect(first.diagnostics.decodedFrameCount == 1)
        // The frame is for a place the second player has left: showing it
        // would undo the seek.
        #expect(second.image == nil)
        #expect(await decoder.decodeCounts[0] == 1)
    }

    // MARK: Helpers

    /// Waits for the decodes in flight, like `waitUntilFull()`, but gives up
    /// after a few dozen of them: a store that asks for a refused frame again
    /// never runs out of decodes, and the test should fail rather than hang.
    private func waitForDecodes(of player: AnimatedImagePlayer) async {
        for _ in 0..<32 {
            guard let decode = player.store.currentDecode else { return }
            await decode.value
        }
    }

    private func makePlayer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options()
    ) -> AnimatedImagePlayer {
        let player = AnimatedImagePlayer(source: source, options: options, clock: ManualClock(), pool: pool)
        player.play()
        return player
    }

    /// A player nothing has started, on a clock the test drives.
    private func makeIdlePlayer(
        source: AnimatedImageSource,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options(),
        decoder: (any AnimatedImageFrameDecoding)? = nil
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let clock = ManualClock()
        let player = AnimatedImagePlayer(
            source: source,
            options: options,
            clock: clock,
            pool: pool,
            power: AnimatedImagePowerMonitor(isThrottling: false),
            decoder: decoder
        )
        return (player, clock)
    }

    private func makeSource(frameCount: Int, size: CGSize = CGSize(width: 32, height: 32)) throws -> AnimatedImageSource {
        try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: frameCount, size: size)))
    }
}

/// A decoder that refuses some of the frames, the way one reading a truncated
/// animation does, and counts what it was asked for.
private actor RefusingFrameDecoder: AnimatedImageFrameDecoding {
    private let decoder: AnimatedImageFrameDecoder
    private let refused: Set<Int>

    /// The number of times each frame was asked for.
    private(set) var requests: [Int: Int] = [:]

    init(source: AnimatedImageSource, refusing refused: Set<Int>) {
        self.decoder = AnimatedImageFrameDecoder(source: source)
        self.refused = refused
    }

    func decode(at index: Int) async -> CGImage? {
        requests[index, default: 0] += 1
        guard !refused.contains(index) else {
            return nil
        }
        return await decoder.decode(at: index)
    }
}

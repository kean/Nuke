// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImagePlayerTests {
    // MARK: Starting Up

    @Test func isPausedUntilPlayIsCalled() {
        let (player, clock) = AnimatedImageTest.makePlayer()

        #expect(player.isPlaying == false)
        clock.tick(10)
        #expect(player.currentFrameIndex == 0)
    }

    @Test func decodesTheFirstFrameWithoutPlaying() async {
        let (player, _) = AnimatedImageTest.makePlayer()
        #expect(player.image == nil)

        await player.buffer.waitUntilFull()

        #expect(player.image != nil)
        #expect(player.currentFrameIndex == 0)
    }

    @Test func doesNotFillTheBufferUntilItPlays() async {
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 8)

        await player.buffer.waitUntilFull()

        // The first frame is on screen, but nothing is playing, so the rest of
        // the window is not worth decoding or holding on to.
        #expect(player.image != nil)
        #expect(player.diagnostics.bufferCapacity == AnimatedImageFrameBuffer.idleCapacity)
        #expect(player.diagnostics.bufferedFrameCount == AnimatedImageFrameBuffer.idleCapacity)

        player.play()
        await player.buffer.waitUntilFull()

        #expect(player.diagnostics.bufferedFrameCount == 8)
    }

    @Test func playStartsTheClock() {
        let (player, clock) = AnimatedImageTest.makePlayer()

        player.play()

        #expect(player.isPlaying)
        #expect(clock.isPaused == false)
    }

    @Test func doesNotAdvanceUntilTheFirstFrameIsOnScreen() async {
        let (player, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.1, count: 4))
        player.play()

        // The clock is running, but nothing has been decoded yet: this time
        // belongs to the frame that is still on its way.
        clock.tick(0.5)
        #expect(player.currentFrameIndex == 0)
        #expect(player.completedLoopCount == 0)

        await player.buffer.waitUntilFull()
        clock.tick(0.1)

        #expect(player.currentFrameIndex == 1)
    }

    // MARK: Timing

    @Test func holdsTheFrameUntilItsDelayHasPassed() async {
        let (player, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.1, count: 4))
        player.play()
        await player.buffer.waitUntilFull()

        clock.tick(0.05)
        #expect(player.currentFrameIndex == 0)

        clock.tick(0.06)
        #expect(player.currentFrameIndex == 1)
    }

    @Test func accumulatesTicksSmallerThanTheDelay() async {
        let (player, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.1, count: 4))
        player.play()
        await player.buffer.waitUntilFull()

        // A 0.1s frame on a 60 Hz display: the frame lasts as many refreshes as
        // it takes to cover the delay, and not one fewer.
        for _ in 0..<5 { clock.tick(1.0 / 60) }
        #expect(player.currentFrameIndex == 0)

        for _ in 0..<2 { clock.tick(1.0 / 60) }
        #expect(player.currentFrameIndex == 1)
    }

    @Test func honorsPerFrameDelays() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, delays: [0.1, 0.5, 0.1])
        player.play()
        await player.buffer.waitUntilFull()

        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)

        clock.tick(0.2) // Not enough for the long frame
        #expect(player.currentFrameIndex == 1)

        clock.tick(0.3)
        #expect(player.currentFrameIndex == 2)
    }

    @Test func playbackRateScalesTime() async {
        var options = AnimatedImagePlayer.Options()
        options.playbackRate = 2
        let (player, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.1, count: 4), options: options)
        player.play()
        await player.buffer.waitUntilFull()

        clock.tick(0.1) // Worth 0.2s of animation
        #expect(player.currentFrameIndex == 2)
    }

    @Test func pauseStopsAdvancing() async {
        let (player, clock) = AnimatedImageTest.makePlayer()
        player.play()
        await player.buffer.waitUntilFull()
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)

        player.pause()
        clock.tick(10)

        #expect(player.isPlaying == false)
        #expect(player.currentFrameIndex == 1)
    }

    // MARK: Falling Behind

    @Test func skipsTheFramesItIsBehindOn() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 8, delays: Array(repeating: 0.1, count: 8))
        player.play()
        await player.buffer.waitUntilFull()

        clock.tick(0.35) // Three frames' worth in one go

        #expect(player.currentFrameIndex == 3)
        // One frame displayed, the two it passed over counted as skipped.
        #expect(player.diagnostics.skippedFrameCount == 2)
        #expect(player.diagnostics.displayedFrameCount == 2) // The first frame, plus this one
    }

    @Test func doesNotReplayTimeItSleptThrough() async {
        // A player that comes back from the background gets one enormous tick.
        // Racing through it would look like a fast-forward, so it is capped.
        var options = AnimatedImagePlayer.Options()
        options.maxTimeStep = 0.25
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 8, delays: Array(repeating: 0.1, count: 8), options: options)
        player.play()
        await player.buffer.waitUntilFull()

        clock.tick(60)

        #expect(player.currentFrameIndex == 2)
        #expect(player.diagnostics.playbackTime == 0.25)
    }

    @Test func stopsCatchingUpAfterAFullLoop() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 4, delays: Array(repeating: 0.1, count: 4))
        player.play()
        await player.buffer.waitUntilFull()

        clock.tick(1) // Ten frames' worth of a four-frame animation

        #expect(player.currentFrameIndex == 0)
        #expect(player.completedLoopCount == 1)
    }

    @Test func countsAMissWhenTheFrameIsNotDecodedYet() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 4, options: .twoFrameBuffer)
        player.play()
        await player.buffer.waitUntilFull()

        // Two frames fit in the window, so the third one cannot be ready when
        // the playhead arrives at it.
        clock.tick(0.25)

        #expect(player.currentFrameIndex == 2)
        #expect(player.diagnostics.bufferMissCount == 1)
    }

    @Test func displaysALateFrameWhenItArrives() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 4, options: .twoFrameBuffer)
        player.play()
        await player.buffer.waitUntilFull()
        clock.tick(0.25)
        let stale = AnimatedImageTest.firstPixel(of: player.image)
        #expect(player.diagnostics.bufferMissCount == 1)

        await player.buffer.waitUntilFull()

        #expect(player.currentFrameIndex == 2)
        #expect(AnimatedImageTest.firstPixel(of: player.image) != stale)
    }

    @Test func playsAtTheSpeedOfADecoderThatCannotKeepUp() async throws {
        // GIVEN an animation whose window holds two frames, so that nothing can
        // be decoded far enough ahead
        let (player, clock, decoder) = AnimatedImageTest.makeGatedPlayer(
            frameCount: 8, delays: Array(repeating: 0.1, count: 8), options: .twoFrameBuffer
        )
        let first = try #require(player.buffer.currentDecode)
        await decoder.release(0)
        await first.value
        let poster = AnimatedImageTest.firstPixel(of: player.image)

        // WHEN a frame takes longer to decode than the frames before it are
        // shown for, so the playhead runs past it
        player.play()
        let late = try #require(player.buffer.currentDecode)
        for _ in 0..<3 { clock.tick(0.1) }
        #expect(player.currentFrameIndex == 3)
        #expect(player.diagnostics.bufferMissCount == 3)
        await decoder.release(1)
        await late.value

        // THEN the frame is displayed and the playhead moves back to it. Held
        // to the wall clock, every frame after this one would decode just as
        // late and be dropped just as well, and the animation would stop.
        #expect(player.currentFrameIndex == 1)
        #expect(player.diagnostics.displayedFrameCount == 2)
        #expect(AnimatedImageTest.firstPixel(of: player.image) != poster)
    }

    // MARK: Frames

    @Test func showsADifferentImageForEachFrame() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3)
        await player.buffer.waitUntilFull()
        let first = AnimatedImageTest.firstPixel(of: player.image)
        #expect(first != nil)

        player.play()
        clock.tick(0.1)

        #expect(AnimatedImageTest.firstPixel(of: player.image) != first)
    }

    @Test func callsOnFrameForEveryDisplayedFrame() async {
        let (player, clock) = AnimatedImageTest.makePlayer()
        var count = 0
        player.onFrame = { _ in count += 1 }
        player.play()
        await player.buffer.waitUntilFull()
        #expect(count == 1)

        clock.tick(0.1)
        clock.tick(0.1)

        #expect(count == 3)
    }

    // MARK: Looping

    @Test func loopsForever() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, loopCount: 0)
        await player.buffer.waitUntilFull()
        var loops: [Int] = []
        player.onLoop = { loops.append($0) }
        player.play()

        for _ in 0..<9 { clock.tick(0.1) }

        #expect(loops == [1, 2, 3])
        #expect(player.isFinished == false)
        #expect(player.isPlaying)
    }

    @Test func stopsAfterTheNumberOfLoopsTheImageAsksFor() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, loopCount: 2)
        await player.buffer.waitUntilFull()
        var isFinished = false
        player.onFinish = { isFinished = true }
        player.play()

        for _ in 0..<6 { clock.tick(0.1) }

        #expect(isFinished)
        #expect(player.isFinished)
        #expect(player.isPlaying == false)
        #expect(player.completedLoopCount == 2)
        // It stops on the last frame rather than snapping back to the first.
        #expect(player.currentFrameIndex == 2)
    }

    @Test func repeatCountOverridesTheImage() async {
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(1)
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, loopCount: 0, options: options)
        player.play()
        await player.buffer.waitUntilFull()

        for _ in 0..<3 { clock.tick(0.1) }

        #expect(player.isFinished)
        #expect(player.completedLoopCount == 1)
    }

    @Test func infiniteOverridesTheImagesLoopCount() async {
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .infinite
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, loopCount: 1, options: options)
        player.play()
        await player.buffer.waitUntilFull()

        for _ in 0..<9 { clock.tick(0.1) }

        #expect(player.isFinished == false)
        #expect(player.completedLoopCount == 3)
    }

    @Test func playDoesNothingAfterFinishing() async {
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(1)
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 2, options: options)
        player.play()
        await player.buffer.waitUntilFull()
        for _ in 0..<2 { clock.tick(0.1) }
        #expect(player.isFinished)

        player.play()

        #expect(player.isPlaying == false)
    }

    @Test func restartPlaysItAgainFromTheStart() async {
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(1)
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 2, options: options)
        player.play()
        await player.buffer.waitUntilFull()
        for _ in 0..<2 { clock.tick(0.1) }
        #expect(player.isFinished)

        player.restart()

        #expect(player.isFinished == false)
        #expect(player.isPlaying)
        #expect(player.currentFrameIndex == 0)
        #expect(player.completedLoopCount == 0)
    }

    // MARK: Seeking

    @Test func seekMovesToTheFrame() async {
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 5)
        await player.buffer.waitUntilFull()

        player.seek(toFrame: 3)
        await player.buffer.waitUntilFull()

        #expect(player.currentFrameIndex == 3)
        #expect(player.image != nil)
    }

    @Test func seekClampsToTheAnimation() async {
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 5)

        player.seek(toFrame: 99)
        #expect(player.currentFrameIndex == 4)

        player.seek(toFrame: -3)
        #expect(player.currentFrameIndex == 0)
    }

    @Test func seekResetsTheTimeTowardsTheNextFrame() async {
        let (player, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.1, count: 4))
        player.play()
        await player.buffer.waitUntilFull()
        clock.tick(0.09) // Almost a frame's worth of credit

        player.seek(toFrame: 2)
        clock.tick(0.05)

        #expect(player.currentFrameIndex == 2)
    }

    // MARK: Diagnostics

    @Test func reportsBufferAndDecodeStatistics() async throws {
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 4, size: CGSize(width: 16, height: 16))
        player.play()
        await player.buffer.waitUntilFull()

        let diagnostics = player.diagnostics
        #expect(diagnostics.frameCount == 4)
        #expect(diagnostics.bufferedFrameCount == 4)
        #expect(diagnostics.bufferCapacity == 4)
        #expect(diagnostics.isFullyBuffered)
        #expect(diagnostics.decodedFrameCount == 4)
        #expect(diagnostics.bufferedByteCount == 4 * (try #require(AnimatedImageTest.bytesPerFrame(of: player))))
        #expect(diagnostics.lastDecodeDuration > 0)
        #expect(diagnostics.averageDecodeDuration > 0)
        #expect(diagnostics.maxDecodeDuration >= diagnostics.averageDecodeDuration)
    }

    @Test func reportsTheEffectiveFrameRate() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 4, delays: Array(repeating: 0.1, count: 4))
        player.play()
        await player.buffer.waitUntilFull()

        for _ in 0..<4 { clock.tick(0.1) }

        // Four frames over 0.4s of playback, plus the frame shown before the
        // clock started, is a shade over the nominal 10 fps.
        #expect(player.diagnostics.playbackTime == 0.4)
        #expect(player.diagnostics.effectiveFrameRate > 9)
    }

    @Test func memoryWarningShrinksTheBuffer() async throws {
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 8)
        player.play()
        await player.buffer.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 8)
        let bytesPerFrame = try #require(AnimatedImageTest.bytesPerFrame(of: player))

        player.reduceMemoryUsage()

        #expect(player.diagnostics.bufferCapacity == 2)
        #expect(player.diagnostics.bufferedFrameCount == 2)
        #expect(player.diagnostics.bufferedByteCount == 2 * bytesPerFrame)
    }
}

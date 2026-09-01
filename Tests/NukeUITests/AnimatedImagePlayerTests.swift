// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Combine
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

        await player.waitUntilFull()

        #expect(player.image != nil)
        #expect(player.currentFrameIndex == 0)
    }

    @Test func doesNotFillTheBufferUntilItPlays() async {
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 8)

        await player.waitUntilFull()

        // The first frame is on screen, but nothing is playing, so the rest of
        // the window is not worth decoding or holding on to.
        #expect(player.image != nil)
        #expect(player.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount)
        #expect(player.diagnostics.bufferedFrameCount == AnimatedImagePlayer.idleFrameCount)

        player.play()
        await player.waitUntilFull()

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

        await player.waitUntilFull()
        clock.tick(0.1)

        #expect(player.currentFrameIndex == 1)
    }

    // MARK: Clock Rate

    @Test func asksTheClockForTwoTicksPerFrame() {
        // 10 frames a second, and a tick to spare for each of them.
        let (_, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.1, count: 4))

        #expect(clock.preferredFrameRate == 20)
    }

    @Test func asksTheClockForARateFasterThanASixtyHertzDisplay() {
        // 20 frames a second: below the rate a display link runs at by default
        // on a 120 Hz display, and the rate the timer clock schedules itself at
        // everywhere.
        let (_, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.05, count: 4))

        #expect(clock.preferredFrameRate == 40)
    }

    @Test func asksForNothingWhenTheAnimationIsFasterThanTheDisplay() {
        // 50 frames a second wants 100 ticks, which no display gives: the clock
        // runs at whatever rate it has and the animation keeps up as it can.
        let (_, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.02, count: 4))

        #expect(clock.preferredFrameRate == 0)
    }

    @Test func asksForAFasterClockWhenPlaybackIsSpedUp() {
        var options = AnimatedImagePlayer.Options()
        options.playbackRate = 2

        let (_, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.1, count: 4), options: options)

        #expect(clock.preferredFrameRate == 40)
    }

    // MARK: Timing

    @Test func holdsTheFrameUntilItsDelayHasPassed() async {
        let (player, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.1, count: 4))
        player.play()
        await player.waitUntilFull()

        clock.tick(0.05)
        #expect(player.currentFrameIndex == 0)

        clock.tick(0.06)
        #expect(player.currentFrameIndex == 1)
    }

    @Test func accumulatesTicksSmallerThanTheDelay() async {
        let (player, clock) = AnimatedImageTest.makePlayer(delays: Array(repeating: 0.1, count: 4))
        player.play()
        await player.waitUntilFull()

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
        await player.waitUntilFull()

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
        await player.waitUntilFull()

        clock.tick(0.1) // Worth 0.2s of animation
        #expect(player.currentFrameIndex == 2)
    }

    @Test func pauseStopsAdvancing() async {
        let (player, clock) = AnimatedImageTest.makePlayer()
        player.play()
        await player.waitUntilFull()
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
        await player.waitUntilFull()

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
        await player.waitUntilFull()

        clock.tick(60)

        #expect(player.currentFrameIndex == 2)
        #expect(player.diagnostics.playbackTime == 0.25)
    }

    @Test func stopsCatchingUpAfterAFullLoop() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 4, delays: Array(repeating: 0.1, count: 4))
        player.play()
        await player.waitUntilFull()

        clock.tick(1) // Ten frames' worth of a four-frame animation

        #expect(player.currentFrameIndex == 0)
        #expect(player.completedLoopCount == 1)
    }

    @Test func countsAMissWhenTheFrameIsNotDecodedYet() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 4, options: .twoFrameBuffer)
        player.play()
        await player.waitUntilFull()

        // Two frames fit in the window, so the third one cannot be ready when
        // the playhead arrives at it.
        clock.tick(0.25)

        #expect(player.currentFrameIndex == 2)
        #expect(player.diagnostics.bufferMissCount == 1)
    }

    @Test func displaysALateFrameWhenItArrives() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 4, options: .twoFrameBuffer)
        player.play()
        await player.waitUntilFull()
        clock.tick(0.25)
        let stale = AnimatedImageTest.firstPixel(of: player.image)
        #expect(player.diagnostics.bufferMissCount == 1)

        await player.waitUntilFull()

        #expect(player.currentFrameIndex == 2)
        #expect(AnimatedImageTest.firstPixel(of: player.image) != stale)
    }

    @Test func playsAtTheSpeedOfADecoderThatCannotKeepUp() async throws {
        // GIVEN an animation whose window holds two frames, so that nothing can
        // be decoded far enough ahead
        let (player, clock, decoder) = AnimatedImageTest.makeGatedPlayer(
            frameCount: 8, delays: Array(repeating: 0.1, count: 8), options: .twoFrameBuffer
        )
        let first = try #require(player.store.currentDecode)
        await decoder.release(0)
        await first.value
        let poster = AnimatedImageTest.firstPixel(of: player.image)

        // WHEN a frame takes longer to decode than the frames before it are
        // shown for, so the playhead runs past it
        player.play()
        let late = try #require(player.store.currentDecode)
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

    @Test func framesAreSizedForTheScaleTheyWereDecodedFor() async throws {
        var options = AnimatedImagePlayer.Options()
        options.scale = 2
        let (player, _) = AnimatedImageTest.makePlayer(size: CGSize(width: 16, height: 16), options: options)
        await player.waitUntilFull()

        // A 16-pixel frame at scale 2 is 8 points across. One that reports its
        // pixel size instead draws at twice the size wherever nothing rescales
        // it – which on AppKit was every frame, because `NSImage` carries the
        // scale in its size and it was being given the size in pixels.
        let image = try #require(player.image)
        #expect(image.size == CGSize(width: 8, height: 8))
    }

    @Test func showsADifferentImageForEachFrame() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3)
        await player.waitUntilFull()
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
        await player.waitUntilFull()
        #expect(count == 1)

        clock.tick(0.1)
        clock.tick(0.1)

        #expect(count == 3)
    }

    // MARK: Looping

    @Test func loopsForever() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, loopCount: 0)
        await player.waitUntilFull()
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
        await player.waitUntilFull()
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
        await player.waitUntilFull()

        for _ in 0..<3 { clock.tick(0.1) }

        #expect(player.isFinished)
        #expect(player.completedLoopCount == 1)
    }

    @Test func infiniteOverridesTheImagesLoopCount() async {
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .infinite
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, loopCount: 1, options: options)
        player.play()
        await player.waitUntilFull()

        for _ in 0..<9 { clock.tick(0.1) }

        #expect(player.isFinished == false)
        #expect(player.completedLoopCount == 3)
    }

    @Test func playDoesNothingAfterFinishing() async {
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(1)
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 2, options: options)
        player.play()
        await player.waitUntilFull()
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
        await player.waitUntilFull()
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
        await player.waitUntilFull()

        player.seek(toFrame: 3)
        await player.waitUntilFull()

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
        await player.waitUntilFull()
        clock.tick(0.09) // Almost a frame's worth of credit

        player.seek(toFrame: 2)
        clock.tick(0.05)

        #expect(player.currentFrameIndex == 2)
    }

    @Test func seekSurvivesTheDecodeItInterrupts() async throws {
        // GIVEN a decoder still working on the frame the animation was on
        let (player, _, decoder) = AnimatedImageTest.makeGatedPlayer(
            frameCount: 8, delays: Array(repeating: 0.1, count: 8), options: .twoFrameBuffer
        )
        let poster = try #require(player.store.currentDecode)
        await decoder.release(0)
        await poster.value
        let firstFrame = AnimatedImageTest.firstPixel(of: player.image)
        player.play()
        let interrupted = try #require(player.store.currentDecode)

        // WHEN the playhead is moved somewhere else and that decode lands after
        player.seek(toFrame: 5)
        await decoder.release(1)
        await interrupted.value

        // THEN the player is where it was asked to go, still showing the frame
        // it had. Frame 1 arriving late otherwise reads as the decoder falling
        // behind, which is the one case where the playhead moves back to meet
        // it – and with a sliding window, where the frame a seek lands on is
        // almost never already decoded, that undid every seek.
        #expect(player.currentFrameIndex == 5)
        #expect(AnimatedImageTest.firstPixel(of: player.image) == firstFrame)
    }

    @Test func restartSurvivesTheDecodeItInterrupts() async throws {
        let (player, _, decoder) = AnimatedImageTest.makeGatedPlayer(
            frameCount: 8, delays: Array(repeating: 0.1, count: 8), options: .twoFrameBuffer
        )
        let poster = try #require(player.store.currentDecode)
        await decoder.release(0)
        await poster.value
        player.play()
        player.seek(toFrame: 3)
        let interrupted = try #require(player.store.currentDecode)

        player.restart()
        await decoder.release(3)
        await interrupted.value

        #expect(player.currentFrameIndex == 0)
    }

    @Test func seekPlaysAnAnimationThatHasFinished() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, loopCount: 1)
        await player.waitUntilFull()
        player.play()
        for _ in 0..<3 { clock.tick(0.1) }
        #expect(player.isFinished)

        // Finished with the loops it was asked for, not with the animation:
        // without this, seeking and playing was a silent no-op and the only way
        // back was `restart()`, which gives up the position.
        player.seek(toFrame: 1)
        player.play()

        #expect(player.isFinished == false)
        #expect(player.isPlaying)
        #expect(player.currentFrameIndex == 1)
    }

    @Test func stopsOnItsLastFrameWithASlowDecoder() async throws {
        // GIVEN an animation that plays once, with a decoder that can't keep up
        var options = AnimatedImagePlayer.Options.twoFrameBuffer
        options.repeatCount = .finite(1)
        let (player, clock, decoder) = AnimatedImageTest.makeGatedPlayer(
            frameCount: 3, delays: Array(repeating: 0.1, count: 3), options: options
        )
        let poster = try #require(player.store.currentDecode)
        await decoder.release(0)
        await poster.value

        // WHEN it runs to the end and a frame it ran past arrives afterwards
        player.play()
        let late = try #require(player.store.currentDecode)
        for _ in 0..<3 { clock.tick(0.1) }
        #expect(player.isFinished)
        await decoder.release(1)
        await late.value

        // THEN it stays on the frame it stopped on. The playhead moves back to
        // meet a late frame only while the animation is running: a player that
        // has stopped is on the frame it is on deliberately, and one that never
        // reaches its last frame has not played the loop it was asked for.
        #expect(player.currentFrameIndex == 2)
        #expect(player.isFinished)
    }

    // MARK: Decode Priority

    @Test func decodesTheFrameItIsWaitingOnAheadOfTheRestOfTheWindow() async {
        let (player, _, decoder) = AnimatedImageTest.makeGatedPlayer(frameCount: 4)

        // Nothing is on screen until frame 0 lands.
        #expect(await decoder.priority(of: 0) == .userInitiated)

        player.play()
        await decoder.release(0)

        // The rest of the window is read-ahead: a screen full of animations
        // filling their buffers should queue behind the app's own work.
        #expect(await decoder.priority(of: 1) == .utility)
    }

    @Test func decodesTheFrameASeekLandedOnAheadOfTheRestOfTheWindow() async {
        let (player, _, decoder) = AnimatedImageTest.makeGatedPlayer(frameCount: 8)
        player.play()
        await decoder.release(0)
        #expect(await decoder.priority(of: 1) == .utility)

        player.seek(toFrame: 5)

        // The seek made frame 5 the one nothing can be shown without.
        #expect(await decoder.priority(of: 5) == .userInitiated)
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test func raisesTheReadAheadDecodeThePlayheadCatchesUpWith() async {
        let (player, clock, decoder) = AnimatedImageTest.makeGatedPlayer(
            frameCount: 4, delays: Array(repeating: 0.1, count: 4)
        )
        player.play()
        await decoder.release(0)
        #expect(await decoder.priority(of: 1) == .utility)

        // WHEN the playhead reaches the frame while it is still decoding
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)

        // THEN the decode is raised to the priority of a frame that is due
        // rather than left to finish at the priority it was started at. A
        // task's priority is fixed when it is made; this is the store having
        // a task of a higher priority await it.
        #expect(await decoder.escalatedPriority(of: 1) == .userInitiated)
    }

    // MARK: Observation

    @Test func publishesWhenPlaybackStartsAndStops() {
        let (player, _) = AnimatedImageTest.makePlayer()
        var changes = 0
        let observer = player.objectWillChange.sink { changes += 1 }

        player.play()
        #expect(changes == 1)

        player.pause()
        #expect(changes == 2)

        observer.cancel()
    }

    @Test func publishesASeek() async {
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 5)
        await player.waitUntilFull()
        var changes = 0
        let observer = player.objectWillChange.sink { changes += 1 }

        player.seek(toFrame: 3)

        #expect(changes == 1)
        observer.cancel()
    }

    @Test func publishesWhenTheAnimationFinishes() async {
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(1)
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 2, options: options)
        player.play()
        await player.waitUntilFull()
        var changes = 0
        let observer = player.objectWillChange.sink { changes += 1 }

        for _ in 0..<2 { clock.tick(0.1) }

        #expect(player.isFinished)
        #expect(changes > 0)
        observer.cancel()
    }

    @Test func publishesNothingWhileTheAnimationRuns() async {
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 4)
        player.play()
        await player.waitUntilFull()
        var changes = 0
        let observer = player.objectWillChange.sink { changes += 1 }

        for _ in 0..<6 { clock.tick(0.1) }

        // Six frames and a completed loop, and nothing was published: a view
        // observing the player is not redrawn on the frame clock.
        #expect(player.currentFrameIndex == 2)
        #expect(player.completedLoopCount == 1)
        #expect(changes == 0)
        observer.cancel()
    }

    // MARK: Diagnostics

    @Test func reportsBufferAndDecodeStatistics() async throws {
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 4, size: CGSize(width: 16, height: 16))
        player.play()
        await player.waitUntilFull()

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
        await player.waitUntilFull()

        for _ in 0..<4 { clock.tick(0.1) }

        // Four frames over 0.4s of playback, plus the frame shown before the
        // clock started, is a shade over the nominal 10 fps.
        #expect(player.diagnostics.playbackTime == 0.4)
        #expect(player.diagnostics.effectiveFrameRate > 9)
    }

    @Test func memoryWarningShrinksTheBuffer() async throws {
        let pool = AnimatedImageFramePool()
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 8, pool: pool)
        player.play()
        await player.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 8)
        let bytesPerFrame = try #require(AnimatedImageTest.bytesPerFrame(of: player))

        pool.reduceMemoryUsage()

        #expect(player.diagnostics.bufferCapacity == 2)
        #expect(player.diagnostics.bufferedFrameCount == 2)
        #expect(player.diagnostics.bufferedByteCount == 2 * bytesPerFrame)
    }

    @Test func givesTheBufferBackOnceTheMemoryPressureHasPassed() async throws {
        let pool = AnimatedImageFramePool()
        pool.memoryPressureGracePeriod = 0.01
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 8, pool: pool)
        player.play()
        await player.waitUntilFull()

        pool.reduceMemoryUsage()
        #expect(player.diagnostics.bufferCapacity == 2)

        // A memory warning arrives while the app is active, usually on the very
        // screen the animation is on. Waiting for the app to be backgrounded
        // and come back is waiting for something that mostly doesn't happen,
        // and an animation that is up all session – a sticker, a spinner –
        // would re-decode every frame of every loop for the rest of it.
        for _ in 0..<200 where player.diagnostics.bufferCapacity == 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(player.diagnostics.bufferCapacity == 8)
        await player.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 8)
    }

    @Test func releasingTheBufferHoldsTheFrameOnScreenAndTheNextOne() async throws {
        let (player, _) = AnimatedImageTest.makePlayer(frameCount: 8)
        player.play()
        await player.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 8)

        player.pause()
        player.keepsFullBuffer = false

        // What a view that has scrolled off screen costs: a still, and the
        // frame that lets playback resume without a stall.
        #expect(player.diagnostics.bufferedFrameCount == AnimatedImagePlayer.idleFrameCount)

        player.play()
        await player.waitUntilFull()

        #expect(player.diagnostics.bufferedFrameCount == 8)
    }
}

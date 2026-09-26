// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

/// The playback contract of ``AnimatedImagePlayer`` at its edges: the order the
/// callbacks arrive in, the repeat counts and rates that aren't the usual ones,
/// frames the decoder refuses, and what a player leaves behind.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImagePlayerPlaybackTests {
    /// A pool of its own for every test: what a player holds depends on what
    /// every other animation on screen is asking for.
    private let pool = AnimatedImageFramePool()

    // MARK: Finishing

    @Test func reportsTheLastLoopBeforeItFinishes() async {
        // GIVEN an animation that asks to be played twice
        let (player, clock) = makePlayer(frameCount: 3, loopCount: 2)
        var events: [String] = []
        player.onLoop = { events.append("loop \($0)") }
        player.onFinish = { [unowned player, unowned clock] in
            // By the time it is told, the player has stopped...
            #expect(player.isFinished)
            #expect(player.isPlaying == false)
            #expect(clock.isPaused)
            events.append("finish")
        }
        player.play()
        await player.waitUntilFull()

        // WHEN it plays both loops
        for _ in 0..<6 { clock.tick(0.1) }

        // THEN the last loop is reported like every other one, and then the
        // finish, once
        #expect(events == ["loop 1", "loop 2", "finish"])

        // ...and nothing is reported by a clock that ticks on regardless.
        clock.isPaused = false
        for _ in 0..<3 { clock.tick(0.1) }
        #expect(events == ["loop 1", "loop 2", "finish"])
    }

    @Test(arguments: [0, -3])
    func aRepeatCountBelowOnePlaysOnce(_ count: Int) async {
        // "Play a set number of times" has no meaning below one, and never
        // playing at all is not what anybody asking for zero plays wants.
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(count)
        let (player, clock) = makePlayer(frameCount: 3, options: options)
        player.play()
        await player.waitUntilFull()

        clock.tick(0.1)
        clock.tick(0.1)
        #expect(player.isFinished == false)
        clock.tick(0.1)

        #expect(player.isFinished)
        #expect(player.completedLoopCount == 1)
        #expect(player.currentFrameIndex == 2)
    }

    @Test func playsAGIFWithNoLoopCountOnce() async throws {
        // A GIF with no Netscape extension asks to be played once, and is, the
        // way a browser plays it.
        let data = Test.animatedGIF(frameCount: 3, loopCount: nil)
        let source = try #require(AnimatedImageSource(data: data))
        let clock = ManualClock()
        let player = AnimatedImagePlayer(source: source, options: .init(), clock: clock, pool: pool, power: noThrottling)
        player.play()
        await player.waitUntilFull()

        for _ in 0..<3 { clock.tick(0.1) }

        #expect(player.isFinished)
        #expect(player.completedLoopCount == 1)
    }

    @Test func canBeRestartedFromTheFinishHandler() async {
        // GIVEN an animation that plays once, and a handler that starts it over
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(1)
        let (player, clock) = makePlayer(frameCount: 3, options: options)
        var finishCount = 0
        player.onFinish = { [unowned player] in
            finishCount += 1
            player.restart()
        }
        player.play()
        await player.waitUntilFull()

        // WHEN it finishes
        for _ in 0..<3 { clock.tick(0.1) }

        // THEN it is playing from the beginning again
        #expect(finishCount == 1)
        #expect(player.isFinished == false)
        #expect(player.isPlaying)
        #expect(player.currentFrameIndex == 0)
        #expect(player.completedLoopCount == 0)
        #expect(clock.isPaused == false)

        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)
    }

    @Test func canBeRestartedFromTheLastLoopHandler() async {
        // GIVEN an animation that plays once, and a loop handler that starts it
        // over
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(1)
        let (player, clock) = makePlayer(frameCount: 3, options: options)
        player.onLoop = { [unowned player] _ in player.restart() }
        var finishCount = 0
        player.onFinish = { finishCount += 1 }
        player.play()
        await player.waitUntilFull()

        // WHEN it plays its one loop
        for _ in 0..<3 { clock.tick(0.1) }

        // THEN it is playing from the beginning again, and it never finished
        #expect(finishCount == 0)
        #expect(player.isFinished == false)
        #expect(player.isPlaying)
        #expect(player.currentFrameIndex == 0)
        #expect(player.completedLoopCount == 0)
        #expect(clock.isPaused == false)

        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)
    }

    @Test func aSeekFromTheLoopHandlerStands() async {
        // GIVEN a handler that skips the first frames on every loop after the
        // first
        let (player, clock) = makePlayer(frameCount: 4)
        player.onLoop = { [unowned player] _ in player.seek(toFrame: 2) }
        var shown: [Int] = []
        player.play()
        await player.waitUntilFull()
        player.onFrame = { [unowned player] _ in shown.append(player.currentFrameIndex) }

        // WHEN the animation wraps around
        for _ in 0..<4 { clock.tick(0.1) }

        // THEN it plays on from the frame the handler asked for
        #expect(player.currentFrameIndex == 2)
        #expect(shown == [1, 2, 3, 0, 2])
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 3)
    }

    @Test func aPauseFromTheLoopHandlerHoldsTheFirstFrame() async {
        // GIVEN a handler that stops the animation after every loop
        let (player, clock) = makePlayer(frameCount: 3)
        var indexes: [Int] = []
        player.onLoop = { [unowned player] _ in
            // The player is already on the first frame when it is told
            indexes.append(player.currentFrameIndex)
            player.pause()
        }
        player.play()
        await player.waitUntilFull()

        // WHEN the animation wraps around
        for _ in 0..<3 { clock.tick(0.1) }

        // THEN it is paused on the first frame, and stays there
        #expect(indexes == [0])
        #expect(player.isPlaying == false)
        #expect(clock.isPaused)
        #expect(player.currentFrameIndex == 0)
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 0)
        #expect(player.completedLoopCount == 1)
    }

    // MARK: Seeking

    @Test func seekingToADecodedFrameShowsItAtOnce() async throws {
        let (player, _) = makePlayer(frameCount: 4)
        player.play()
        await player.waitUntilFull()
        var frames: [PlatformImage] = []
        player.onFrame = { frames.append($0) }

        player.seek(toFrame: 2)

        // Not on the next tick: a scrubber drawing the frame it asked for.
        #expect(frames.count == 1)
        let frame = try #require(player.store.frame(at: 2))
        #expect(AnimatedImageTest.firstPixel(of: frames.first) == AnimatedImageTest.firstPixel(of: frame))
        #expect(player.image === frames.first)
    }

    @Test func seekingToTheFrameOnScreenPublishesButDoesNotRedrawIt() async {
        let (player, _) = makePlayer(frameCount: 4)
        await player.waitUntilFull()
        let displayed = player.diagnostics.displayedFrameCount
        var frameCount = 0
        player.onFrame = { _ in frameCount += 1 }
        var changes = 0
        let observer = player.objectWillChange.sink { changes += 1 }

        player.seek(toFrame: 0)

        #expect(frameCount == 0)
        #expect(player.diagnostics.displayedFrameCount == displayed)
        // A seek is published whether or not it moves the playhead.
        #expect(changes == 1)
        observer.cancel()
    }

    @Test func seekingKeepsTheLoopCountAndDoesNotStartPlayback() async {
        // `completedLoopCount` counts since the player was created; only
        // `restart()` starts it over.
        let (player, clock) = makePlayer(frameCount: 3)
        player.play()
        await player.waitUntilFull()
        for _ in 0..<4 { clock.tick(0.1) }
        #expect(player.completedLoopCount == 1)
        player.pause()

        player.seek(toFrame: 2)

        #expect(player.completedLoopCount == 1)
        #expect(player.isPlaying == false)
        #expect(clock.isPaused)
    }

    // MARK: Timing

    @Test func theWaitForTheFirstFrameIsNotPlaybackTime() async {
        let (player, clock) = makePlayer(frameCount: 4)
        player.play()

        // Nothing is decoded yet: the clock runs, but nothing is on screen for
        // the time to count against.
        clock.tick(0.5)
        #expect(player.diagnostics.playbackTime == 0)
        #expect(player.diagnostics.effectiveFrameRate == 0)

        await player.waitUntilFull()
        clock.tick(0.05)
        #expect(player.diagnostics.playbackTime == 0.05)
    }

    @Test(arguments: [0, -1, Double.nan, Double.infinity])
    func aRateThatIsNotForwardHoldsTheFrame(_ rate: Double) async {
        var options = AnimatedImagePlayer.Options()
        options.playbackRate = rate
        let (player, clock) = makePlayer(frameCount: 4, options: options)
        player.play()
        await player.waitUntilFull()

        for _ in 0..<10 { clock.tick(0.1) }

        // Still playing – nothing stopped it – but not going anywhere, and not
        // counting time it didn't play.
        #expect(player.isPlaying)
        #expect(player.currentFrameIndex == 0)
        #expect(player.diagnostics.playbackTime == 0)
    }

    @Test(arguments: [1e9, 1e17])
    func aHugeRatePlaysAtMostALoopPerTick(_ rate: Double) async {
        var options = AnimatedImagePlayer.Options()
        options.playbackRate = rate
        // A finite repeat count, so that a tick with no bound on its work ends
        // and the test fails rather than hangs.
        let (player, clock) = makePlayer(frameCount: 4, loopCount: 1000, options: options)
        player.play()
        await player.waitUntilFull()

        clock.tick(1.0 / 60)

        // The display shows one frame per tick however fast the animation is
        // asked to run, so there is nothing to gain past a loop of frames –
        // and at these rates the tick would otherwise not return.
        #expect(player.completedLoopCount == 1)
        #expect(player.currentFrameIndex == 0)
        #expect(player.isPlaying)
    }

    @Test func slowingDownHoldsEachFrameLonger() async {
        var options = AnimatedImagePlayer.Options()
        options.playbackRate = 0.5
        let (player, clock) = makePlayer(frameCount: 4, options: options)
        player.play()
        await player.waitUntilFull()

        clock.tick(0.1)
        #expect(player.currentFrameIndex == 0)
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)

        // The clock is not slowed down with it: a slower animation needs no
        // fewer ticks to land each frame on one.
        #expect(clock.preferredFrameRate == 20)
    }

    @Test func asksTheClockForTwoTicksPerItsShortestFrame() {
        // One quick frame among slow ones still has to land on a tick.
        let (_, clock) = makePlayer(frameCount: 4, delays: [0.5, 0.05, 0.5, 0.5])

        #expect(clock.preferredFrameRate == 40)
    }

    // MARK: Frames the Decoder Refuses

    @Test func holdsThePreviousFrameThroughAFrameTheDecoderRefuses() async {
        // GIVEN an animation whose second frame can't be decoded
        let (player, clock) = makeRefusingPlayer(frameCount: 4, refused: [1])
        player.play()
        await player.waitUntilFull()
        #expect(player.isFrameBuffered(1) == false)
        let first = AnimatedImageTest.firstPixel(of: player.image)

        // WHEN it is due
        clock.tick(0.1)

        // THEN the playhead moves on, with the frame before it still on screen
        // for its delay, and the frame counted as one that wasn't there in
        // time
        #expect(player.currentFrameIndex == 1)
        #expect(AnimatedImageTest.firstPixel(of: player.image) == first)
        #expect(player.diagnostics.displayedFrameCount == 1)
        #expect(player.diagnostics.bufferMissCount == 1)

        // ...and the frame after it is shown on time: nothing waits for a
        // frame that isn't coming.
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 2)
        #expect(AnimatedImageTest.firstPixel(of: player.image) == Self.framePixel(at: 2))
    }

    @Test func startsWithoutAFirstFrameTheDecoderRefuses() async {
        let (player, clock) = makeRefusingPlayer(frameCount: 4, refused: [0])
        player.play()
        await player.waitUntilFull()
        #expect(player.image == nil)

        // The time counts against a frame that isn't pending even though it
        // isn't on screen, or the animation would never start.
        clock.tick(0.1)

        #expect(player.currentFrameIndex == 1)
        #expect(AnimatedImageTest.firstPixel(of: player.image) == Self.framePixel(at: 1))
    }

    @Test func finishesAnAnimationWithNoFrameToShow() async {
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(1)
        let (player, clock) = makeRefusingPlayer(frameCount: 3, refused: [0, 1, 2], options: options)
        player.play()
        await player.waitUntilFull()

        for _ in 0..<3 { clock.tick(0.1) }

        #expect(player.image == nil)
        #expect(player.isFinished)
        #expect(player.store.currentDecode == nil) // Nothing is retried
    }

    // MARK: Frames

    @Test func handsTheFrameToTheViewAndTheOwnerOnceItIsTheImage() async {
        // Both channels get every frame, and by the time either is called the
        // player reports the frame as its image.
        let (player, _) = makePlayer(frameCount: 4)
        var calls: [String] = []
        player.onFrameForDisplay = { [unowned player] image in
            #expect(player.image === image)
            calls.append("view")
        }
        player.onFrame = { [unowned player] image in
            #expect(player.image === image)
            calls.append("owner")
        }

        await player.waitUntilFull()

        #expect(calls.sorted() == ["owner", "view"])
    }

    @Test func aScaleOfZeroDrawsTheFramesAtTheirPixelSize() async throws {
        // Where the frames can't be scaled, both platforms draw them as they
        // are rather than at an infinite size.
        var options = AnimatedImagePlayer.Options()
        options.scale = 0
        let (player, _) = makePlayer(frameCount: 2, size: CGSize(width: 16, height: 16), options: options)

        await player.waitUntilFull()

        let image = try #require(player.image)
        #expect(image.size == CGSize(width: 16, height: 16))
    }

    // MARK: Resuming

    @Test func resumingFromAnotherPlayerCarriesThePlayheadAndTheLoops() async {
        // GIVEN a player halfway through its second loop
        let (previous, clock) = makePlayer(frameCount: 4)
        previous.play()
        await previous.waitUntilFull()
        for _ in 0..<6 { clock.tick(0.1) }
        #expect(previous.completedLoopCount == 1)
        #expect(previous.currentFrameIndex == 2)

        // WHEN its frames are decoded again at another size
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 4
        let player = AnimatedImagePlayer(source: previous.source, options: options, clock: ManualClock(), pool: pool, power: noThrottling)
        player.resume(from: previous)

        // THEN it is the same animation, in the same place
        #expect(player.currentFrameIndex == 2)
        #expect(player.completedLoopCount == 1)
        #expect(player.isFinished == false)
    }

    @Test func resumingFromAFinishedPlayerStaysFinished() async {
        // GIVEN a player that has played the one loop it was asked for
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(1)
        let (previous, clock) = makePlayer(frameCount: 3, options: options)
        previous.play()
        await previous.waitUntilFull()
        for _ in 0..<3 { clock.tick(0.1) }
        #expect(previous.isFinished)

        // WHEN it is taken over at another size
        options.maxPixelSize = 4
        let player = AnimatedImagePlayer(source: previous.source, options: options, clock: ManualClock(), pool: pool, power: noThrottling)
        player.resume(from: previous)

        // THEN a view that grows doesn't play an animation that was over
        #expect(player.isFinished)
        #expect(player.currentFrameIndex == 2)
        player.play()
        #expect(player.isPlaying == false)

        // ...until it is asked to.
        player.restart()
        #expect(player.isPlaying)
        #expect(player.currentFrameIndex == 0)
    }

    // MARK: Buffering

    @Test func aCeilingOfExactlyTheWholeAnimationHoldsItWhole() {
        // The ceiling is on the bytes the frames cost decoded: one that covers
        // every frame to the byte holds the animation whole, and a byte less
        // puts it in a sliding window.
        let source = Test.animatedGIFSource(frameCount: 8)
        var options = AnimatedImagePlayer.Options()
        options.maxBufferSize = 8 * source.bytesPerFrame
        let whole = AnimatedImagePlayer(source: source, options: options, clock: ManualClock(), pool: pool, power: noThrottling)
        whole.play()

        options.maxBufferSize = 8 * source.bytesPerFrame - 1
        let sliding = AnimatedImagePlayer(source: Test.animatedGIFSource(frameCount: 8), options: options, clock: ManualClock(), pool: pool, power: noThrottling)
        sliding.play()

        #expect(whole.diagnostics.isFullyBuffered)
        #expect(sliding.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1)
    }

    // MARK: Diagnostics

    @Test func reportsTheMemoryTheWindowIsAllowed() {
        // The share of the pool, at what a frame costs decoded at the size it
        // is decoded at: a quarter as much for frames half as wide.
        let (full, _) = makePlayer(frameCount: 4, size: CGSize(width: 64, height: 64))
        var options = AnimatedImagePlayer.Options()
        options.maxPixelSize = 32
        let (downsampled, _) = makePlayer(frameCount: 4, size: CGSize(width: 64, height: 64), options: options)
        full.play()
        downsampled.play()

        #expect(full.diagnostics.bufferByteLimit == full.diagnostics.bufferCapacity * full.source.bytesPerFrame)
        #expect(downsampled.diagnostics.bufferByteLimit == downsampled.diagnostics.bufferCapacity * downsampled.source.bytesPerFrame / 4)
    }

    @Test func countsThePlayersSharingItsFrames() {
        let source = Test.animatedGIFSource(frameCount: 4)
        let first = AnimatedImagePlayer(source: source, options: .init(), clock: ManualClock(), pool: pool, power: noThrottling)
        #expect(first.diagnostics.sharingPlayerCount == 1)

        var second: AnimatedImagePlayer? = AnimatedImagePlayer(source: source, options: .init(), clock: ManualClock(), pool: pool, power: noThrottling)
        #expect(first.diagnostics.sharingPlayerCount == 2)
        #expect(second?.diagnostics.sharingPlayerCount == 2)

        second = nil
        #expect(first.diagnostics.sharingPlayerCount == 1)
    }

    @Test func anEmptySnapshotHasNoFrameRate() {
        // No playback time is not a division by zero.
        let diagnostics = AnimatedImagePlayer.Diagnostics()

        #expect(diagnostics.effectiveFrameRate == 0)
        #expect(diagnostics.playbackTime == 0)
        #expect(diagnostics.displayedFrameCount == 0)
    }

    @Test func optionsDefaultToPlayingTheFileAsItAsks() {
        let options = AnimatedImagePlayer.Options()

        #expect(options.repeatCount == .image)
        #expect(options.playbackRate == 1)
        #expect(options.maxBufferSize == nil)
        #expect(options.maxPixelSize == nil)
        #expect(options.scale == 1)
        #expect(options.frameTransform == nil)
        #expect(options.isSynchronizationEnabled)
        #expect(options.isPowerThrottlingEnabled)
    }

    // MARK: Publishing

    @Test func publishesOnlyWhatChanges() {
        // Asking a playing player to play, or a paused one to pause, is not a
        // change for a SwiftUI view to redraw for.
        let (player, _) = makePlayer(frameCount: 4)
        var changes = 0
        let observer = player.objectWillChange.sink { changes += 1 }

        player.pause()
        #expect(changes == 0)

        player.play()
        player.play()
        #expect(changes == 1)

        player.pause()
        player.pause()
        #expect(changes == 2)
        observer.cancel()
    }

    // MARK: Lifetime

    @Test func goesAwayWithItsClock() async {
        // Neither the clock, the monitor, nor the frames it drew from hold the
        // player: a view that lets go of it is the last owner.
        weak var weakPlayer: AnimatedImagePlayer?
        weak var weakClock: ManualClock?
        do {
            let (player, clock) = makePlayer(frameCount: 4)
            player.play()
            await player.waitUntilFull()
            clock.tick(0.1)
            weakPlayer = player
            weakClock = clock
        }

        #expect(weakPlayer == nil)
        #expect(weakClock == nil)
    }

    @Test func aClockThatOutlivesItsPlayerTicksIntoNothing() async {
        let clock = ManualClock()
        weak var weakPlayer: AnimatedImagePlayer?
        do {
            let source = Test.animatedGIFSource(frameCount: 4)
            let player = AnimatedImagePlayer(source: source, options: .init(), clock: clock, pool: pool, power: noThrottling)
            player.play()
            await player.waitUntilFull()
            weakPlayer = player
        }

        // The tick handler holds the player weakly, and finds it gone.
        #expect(weakPlayer == nil)
        #expect(clock.onTick != nil)
        clock.tick(0.1)
        clock.tick(10)
    }

    // MARK: The Platform's Clock

    @Test func playsEveryFrameInOrderOnThePlatformsClock() async {
        // Every other test here ticks by hand. This one runs on the clock a
        // player built through the public initializer gets – a display link on
        // UIKit, a timer on AppKit – however late its ticks arrive.
        let source = Test.animatedGIFSource(frameCount: 4, delays: Array(repeating: 0.05, count: 4))
        let player = AnimatedImagePlayer(source: source, options: .init(), clock: makeAnimatedImageClock(), pool: pool, power: noThrottling)
        await player.waitUntilFull()

        let shown: [Int] = await withCheckedContinuation { continuation in
            var shown: [Int] = []
            player.onFrame = { [unowned player] _ in
                shown.append(player.currentFrameIndex)
                guard shown.count == 3 else { return }
                player.pause()
                player.onFrame = nil
                continuation.resume(returning: shown)
            }
            player.play()
        }

        #expect(shown == [1, 2, 3])
        // Each of the three frames it moved past had its delay.
        #expect(player.diagnostics.playbackTime >= 0.15 - 0.001)
    }

    // MARK: Helpers

    private let noThrottling = AnimatedImagePowerMonitor(isThrottling: false)

    private func makePlayer(
        frameCount: Int,
        delays: [TimeInterval]? = nil,
        loopCount: Int = 0,
        size: CGSize = CGSize(width: 8, height: 8),
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options()
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        AnimatedImageTest.makePlayer(
            frameCount: frameCount,
            delays: delays,
            loopCount: loopCount,
            size: size,
            options: options,
            pool: pool,
            power: noThrottling
        )
    }

    /// A player of an animation some of whose frames can't be decoded, the
    /// way the frames a truncated file is missing can't.
    private func makeRefusingPlayer(
        frameCount: Int,
        refused: Set<Int>,
        options: AnimatedImagePlayer.Options = AnimatedImagePlayer.Options()
    ) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let source = AnimatedImageSource(
            data: Data(),
            delays: Array(repeating: 0.1, count: frameCount),
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { _ in RefusingFrameDecoder(refused: refused) }
        )!
        let clock = ManualClock()
        let player = AnimatedImagePlayer(source: source, options: options, clock: clock, pool: pool, power: noThrottling)
        return (player, clock)
    }

    /// The pixel the frame at the given index reads back as.
    private static func framePixel(at index: Int) -> [UInt8]? {
        AnimatedImageTest.firstPixel(of: RefusingFrameDecoder.makeFrame(at: index))
    }
}

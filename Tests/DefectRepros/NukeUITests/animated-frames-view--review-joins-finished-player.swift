// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

// BUG: A new player of an animation that plays a set number of times falls
// in behind a player that has already finished it, starts on the last frame,
// and finishes after one frame: the second copy never plays.
//
// `AnimatedImagePlayer.init` starts a joining player at
// `store.leadingIndex()`, which returns the playhead of the first member with
// `keepsFullBuffer == true`. `finish()` stops the clock and sets `isPlaying`
// to `false` but leaves `keepsFullBuffer` alone, so a finished player – on
// screen, stopped on its last frame – still leads. The newcomer starts on that
// last frame with `completedLoopCount == 0`, and its first tick finds no next
// frame (`nextFrameIndex` is `nil` once `completedLoopCount + 1 >= limit`), so
// it finishes at once.
//
// Expected: `leadingIndex()` doc: "The frame a joining player should start
// on, or `nil` when nothing else is playing this animation" – a finished
// player is not playing, and the sharing tests say "A player that hasn't
// started is showing its first frame, not a position worth falling in behind".
// The newcomer should start at frame 0 and play the animation through.
//
// Actual: it starts on frame 3 of 4 and is finished after one tick. With the
// joining bug on top (a joining player never displays the frame it starts
// on), an `AnimatedImageView` showing it keeps its poster, or stays blank,
// and never animates. The case: a play-once sticker or reaction GIF (a GIF
// with a loop count of 1) that has finished in one cell and then appears in
// another – the second cell never plays it.
//
// Source: Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:187-189
// (`leadingIndex()`) and Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:137
// and :432-439 (`finish()` leaves `keepsFullBuffer` set).

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedFramesViewJoinsFinishedPlayerBugTests {
    @Test func aPlayerDoesNotFallInBehindOneThatHasFinished() async throws {
        let pool = AnimatedImageFramePool()
        // Played once, the way the file asks for.
        let source = Test.animatedGIFSource(frameCount: 4, loopCount: 1, size: CGSize(width: 8, height: 8))
        let power = AnimatedImagePowerMonitor(isThrottling: false)

        let firstClock = ManualClock()
        let first = AnimatedImagePlayer(source: source, options: .init(), clock: firstClock, pool: pool, power: power)
        first.play()
        await first.waitUntilFull()
        for _ in 0..<8 where !first.isFinished { firstClock.tick(0.1) }
        #expect(first.isFinished)
        #expect(first.isPlaying == false)
        #expect(first.currentFrameIndex == 3) // Stopped on its last frame

        let secondClock = ManualClock()
        let second = AnimatedImagePlayer(source: source, options: .init(), clock: secondClock, pool: pool, power: power)

        #expect(second.currentFrameIndex == 0) // FAILS: 3

        second.play()
        await second.waitUntilFull()
        secondClock.tick(0.1)

        #expect(second.isFinished == false) // FAILS: finished after a single frame
        #expect(second.isPlaying) // FAILS
    }
}

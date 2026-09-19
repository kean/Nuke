// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

// SUSPECTED BUG: `AnimatedImagePlayer` calls `onLoop` in the middle of updating
// its own state, so the public playback calls a handler makes from there are
// silently undone.
//
// `advance(to:)` (Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:422)
// calls `onLoop?(completedLoopCount)` *before* it assigns `currentFrameIndex =
// index`, and `tick(_:)` then overwrites `elapsed` and displays
// `currentFrameIndex` after the handler has returned. `finish()` (line 432)
// likewise calls `onLoop` before it sets `isFinished = true` / `isPlaying =
// false` and pauses the clock.
//
// 1. `seek(toFrame:)` from `onLoop` – "skip the intro on every loop after the
//    first" – is overwritten: the player displays the frame it seeked to, then
//    snaps back to frame 0 and carries on from there.
//    Expected: `currentFrameIndex == 2` after the wrap.
//    Actual:   `currentFrameIndex == 0` (and frame 2 flashed on screen for
//              zero time via `onFrame`).
//
// 2. `restart()` from `onLoop` on the last loop – "play it again" – is undone
//    by `finish()`: `restart()` resets the loop count and seeks to 0, its
//    `play()` is a no-op because `isPlaying` is still true, and `finish()` then
//    marks the player finished.
//    Expected: playing from frame 0, `isFinished == false`.
//    Actual:   `isFinished == true`, `isPlaying == false`, `currentFrameIndex
//              == 0`, `completedLoopCount == 0` – an inconsistent state: a
//              player that "has played all its loops" having completed none,
//              on its first frame rather than its last.
//
// Both are contract violations of `seek(toFrame:)` ("Displays the frame at the
// given index") and `restart()` ("Returns to the first frame and starts
// playing") when called from the player's own public callback.

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedImagePlayerOnLoopReentrancyBugTests {
    @Test func seekFromOnLoopIsHonored() async {
        let (player, clock) = AnimatedImageTest.makePlayer(
            frameCount: 4,
            power: AnimatedImagePowerMonitor(isThrottling: false)
        )
        player.onLoop = { [unowned player] _ in player.seek(toFrame: 2) }
        player.play()
        await player.waitUntilFull()

        for _ in 0..<4 { clock.tick(0.1) } // Wraps around to the first frame

        #expect(player.currentFrameIndex == 2) // Actual: 0
    }

    @Test func restartFromOnLoopOnTheLastLoopIsHonored() async {
        var options = AnimatedImagePlayer.Options()
        options.repeatCount = .finite(1)
        let (player, clock) = AnimatedImageTest.makePlayer(
            frameCount: 3,
            options: options,
            power: AnimatedImagePowerMonitor(isThrottling: false)
        )
        player.onLoop = { [unowned player] _ in player.restart() }
        player.play()
        await player.waitUntilFull()

        for _ in 0..<3 { clock.tick(0.1) } // Plays its one loop

        #expect(player.isFinished == false) // Actual: true
        #expect(player.isPlaying) // Actual: false
        #expect(player.currentFrameIndex == 0)
        #expect(player.completedLoopCount == 0)
    }
}

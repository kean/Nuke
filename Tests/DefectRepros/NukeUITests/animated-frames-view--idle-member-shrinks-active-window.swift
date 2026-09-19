// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

// BUG: A paused copy of an animation elsewhere in the animation shrinks the
// playing copy's window below the read-ahead, even though the pool handed the
// store enough for both.
//
// `AnimatedImageFrameStore.windowLength` binary-searches for the largest
// window "such that the windows of every member together fit in the
// allotment", but it measures every playhead with the *same* length. A member
// nobody is watching (`keepsFullBuffer == false`) only ever holds
// `idleFrameCount` (2) frames, so the union is over-counted and the playing
// member is cut short.
//
// Numbers: a 20-frame animation, a pool of 5 frames. Player A plays from frame
// 0 and wants its read-ahead (3 frames); player B is paused off screen on
// frame 10 and wants 2. `leastDemand` is 3 + 2 = 5 frames and the pool grants
// exactly that. `windowLength` then asks whether windows of 3 at *both*
// playheads fit (6 > 5), settles on 2, and A is held to 2 frames – short of the
// read-ahead – while one frame of the store's share is never used.
//
// Expected: `windowLength` doc: "the largest window such that the windows of
// every member together fit in the allotment" – windows of 3 (A) and 2 (B)
// fit in 5 – and `leastDemand` doc: "a window of the read-ahead at every
// playhead its members are on".
//
// Actual: A's `bufferCapacity` is 2.
//
// A realistic case: the same sticker twice in a list, one copy scrolled out
// (its cell's view is out of the window, paused on its frame) while the other
// keeps playing and drifts away from it.
//
// Source: Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:331-354

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedFramesViewIdleMemberWindowBugTests {
    @Test func aPausedCopyElsewhereLeavesThePlayingOneItsReadAhead() throws {
        let bytesPerFrame = 32 * 32 * 4
        let pool = AnimatedImageFramePool(costLimit: 5 * bytesPerFrame)
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 20, size: CGSize(width: 32, height: 32))))
        let playing = AnimatedImagePlayer(source: source, options: .init(), clock: ManualClock(), pool: pool)
        playing.play()
        var options = AnimatedImagePlayer.Options()
        options.isSynchronizationEnabled = false
        let paused = AnimatedImagePlayer(source: source, options: options, clock: ManualClock(), pool: pool)
        paused.seek(toFrame: 10)

        // The pool gave the store what it asked for: 3 + 2 frames.
        #expect(playing.store.allotment == 5 * bytesPerFrame)
        #expect(paused.diagnostics.bufferCapacity == AnimatedImagePlayer.idleFrameCount)

        #expect(playing.diagnostics.bufferCapacity == AnimatedImagePlayer.readAheadFrameCount + 1) // FAILS: 2
    }
}

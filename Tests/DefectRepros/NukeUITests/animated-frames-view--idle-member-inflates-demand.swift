// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

// BUG: A paused copy of an animation elsewhere in the animation makes the
// pool hand that animation a share it can't use, and an animation that would
// have fit whole is played out of a window instead.
//
// `AnimatedImageFrameStore.demand` – "what the store would use if the pool had
// it to spare" – counts each playhead's window as reaching the next playhead.
// With a member nobody is watching (it only ever holds 2 frames) the union is
// less than the whole animation, yet more than the store can hold: short of
// the whole animation, `AnimatedImagePlayer.bufferCapacity(windowLength:)` caps
// every window at the read-ahead (3). The pool treats `demand` as "hold it
// whole", grants it, and the frames beyond 3 + 2 are never decoded.
//
// Numbers: pool of 18 frames. Animation S (20 frames): A playing at frame 0,
// B paused at frame 10 → leastDemand 5, demand 12. Animation O (13 frames),
// playing → leastDemand 3, demand 13. The windows take 5 + 3, leaving 10;
// "whole animations, smallest first" gives S its 12 (cost 7) and leaves 3,
// too little for O (cost 10). S then holds 3 + 2 = 5 frames out of its 12,
// while O – which the 10 frames would have held whole – decodes every frame
// again on every loop.
//
// Expected (AnimatedImageFramePool / AnimatedImages.md): the pool "holds as
// many of them whole as fit, smallest first" and "anything between [least]
// and demand buys nothing". O fits whole in what S can't use.
//
// Actual: O's `bufferCapacity` is 3; after both fill, the pool holds 8 frames
// of its 18.
//
// Source: Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:253-285
// (demand) vs Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:252-256
// (bufferCapacity caps a partial window at the read-ahead).

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedFramesViewIdleMemberDemandBugTests {
    @Test func anAnimationThatFitsIsHeldWholeBesideAPausedCopyOfAnother() async throws {
        let bytesPerFrame = 32 * 32 * 4
        let pool = AnimatedImageFramePool(costLimit: 18 * bytesPerFrame)
        let size = CGSize(width: 32, height: 32)
        let shared = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 20, size: size)))
        let other = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 13, size: size)))

        let playing = AnimatedImagePlayer(source: shared, options: .init(), clock: ManualClock(), pool: pool)
        playing.play()
        var options = AnimatedImagePlayer.Options()
        options.isSynchronizationEnabled = false
        let paused = AnimatedImagePlayer(source: shared, options: options, clock: ManualClock(), pool: pool)
        paused.seek(toFrame: 10)
        let single = AnimatedImagePlayer(source: other, options: .init(), clock: ManualClock(), pool: pool)
        single.play()

        // The share S was given, and what it can actually hold of it.
        #expect(playing.store.allotment == 12 * bytesPerFrame)
        #expect(playing.diagnostics.bufferCapacity + paused.diagnostics.bufferCapacity == 5)

        #expect(single.diagnostics.bufferCapacity == 13) // FAILS: 3

        await playing.waitUntilFull()
        await single.waitUntilFull()
        #expect(pool.totalCost > 8 * bytesPerFrame) // FAILS: 8 of 18 frames used
    }
}

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

// SUSPECTED BUG: a player that joins an animation whose frames another player
// has already decoded never displays the frame it starts on.
//
// A player only ever displays a frame from `seek(toFrame:)`, from a tick that
// advances, or from `frameDidDecode(at:)` – the store's callback for a decode
// the player was waiting on. `init` (Sources/NukeUI/AnimatedImages/
// AnimatedImagePlayer.swift:111-146) sets `currentFrameIndex` and joins the
// store, and when the store already holds the frame there is no decode to wait
// for (`AnimatedImageFrameStore.nextNeededIndex` returns nil), so nothing ever
// calls `display(frameAt:)` for it.
//
// Consequences, all for the second view showing an animation – the case frame
// sharing exists for ("the nineteenth view to appear decodes nothing at all"):
// - `image` stays `nil` although the frame is decoded and in memory, which
//   contradicts its doc ("`nil` until the first frame is decoded"), and
//   `onFrame` is never called for it.
// - A player that is never played – `isPlaybackEnabled = false`, or
//   Accessibility › Auto-Play Animated Images off, where the docs promise "the
//   first frame is displayed" – never gets a frame at all: a view given the
//   player with no poster stays blank.
// - A player that is played never shows its starting frame: the first tick's
//   guard (`!store.isPending(currentFrameIndex)`, line 364) counts time
//   against a frame that is not on screen, and the first frame displayed is
//   the one after it – "no frame is ever skipped" (docs, Under the Hood) is
//   violated. With synchronization on, a view joining at frame k shows its
//   poster (frame 0) and then jumps to frame k + 1.
//
// Expected: `second.image != nil` once its frame is in memory, and the first
//           frame it displays is the one it starts on.
// Actual:   `second.image == nil` until the clock advances, and the first
//           frame it displays is `currentFrameIndex + 1`.

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedImagePlayerJoiningDecodedFramesBugTests {
    private let pool = AnimatedImageFramePool()

    @Test func aPlayerJoiningDecodedFramesShowsItsFirstFrame() async {
        let source = Test.animatedGIFSource(frameCount: 4)
        let first = makePlayer(source: source).player
        first.play()
        await first.waitUntilFull()
        #expect(first.image != nil)

        let (second, _) = makePlayer(source: source)
        await second.waitUntilFull()

        #expect(second.diagnostics.bufferedFrameCount > 0) // Its frame is right there
        #expect(second.image != nil) // Actual: nil
    }

    @Test func aPlayerJoiningDecodedFramesDoesNotSkipItsFirstFrame() async {
        let source = Test.animatedGIFSource(frameCount: 4)
        let first = makePlayer(source: source).player
        first.play()
        await first.waitUntilFull()

        let (second, clock) = makePlayer(source: source)
        var shown: [Int] = []
        second.onFrame = { [unowned second] _ in shown.append(second.currentFrameIndex) }
        second.play()
        await second.waitUntilFull()
        clock.tick(0.1)

        #expect(shown == [0, 1]) // Actual: [1]
    }

    private func makePlayer(source: AnimatedImageSource) -> (player: AnimatedImagePlayer, clock: ManualClock) {
        let clock = ManualClock()
        let player = AnimatedImagePlayer(
            source: source,
            options: AnimatedImagePlayer.Options(),
            clock: clock,
            pool: pool,
            power: AnimatedImagePowerMonitor(isThrottling: false)
        )
        return (player, clock)
    }
}

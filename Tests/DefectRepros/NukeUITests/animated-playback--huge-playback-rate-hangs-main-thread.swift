// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

// SUSPECTED BUG: an infinite or very large `Options.playbackRate` hangs the
// main thread on the first tick.
//
// `tick(_:)` (Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:368-403)
// scales the tick by the rate and then walks frame by frame
// (`while elapsed >= source.delays[currentFrameIndex]`), carrying
// `min(remainder, clock.period * options.playbackRate)` over after every frame.
// The work per tick is proportional to the rate, with no bound:
// - `.infinity`: `elapsed` is `inf`, `inf - delay` is `inf`, and the loop never
//   exits for an animation that loops forever with its frames in memory.
// - A finite rate of 1e17: the carry-over is ~1.7e15 s, where `elapsed - 0.1`
//   rounds back to `elapsed` (the ulp is 0.25), so it never exits either.
// - Smaller finite rates finish, after period * rate / delay iterations:
//   1e9 is ~1.7e8 iterations of main-thread work per display refresh.
// `playbackRate` is a public option with no documented range ("The speed
// multiplier. `1` by default."); 0, negative and NaN are already handled – the
// `guard step > 0` holds the frame – so only the large end is unguarded.
//
// The display shows one frame per tick, so nothing is gained by running more
// than a loop's worth of frames in one tick.
//
// Expected: a tick returns after a bounded amount of work – the rate is
//           clamped, or a non-finite one ignored like NaN – so the handler
//           below sees at most a loop or so per tick.
// Actual:   the tick spins through loop after loop; without the escape hatch
//           in `onLoop` (which empties the store so the next frame is late and
//           the loop breaks) the test process hangs on the main thread.

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedImagePlayerHugePlaybackRateBugTests {
    @Test(arguments: [Double.infinity, 1e17])
    func aHugeRateDoesNotSpinTheTick(_ rate: Double) async {
        var options = AnimatedImagePlayer.Options()
        options.playbackRate = rate
        let (player, clock) = AnimatedImageTest.makePlayer(
            frameCount: 4,
            options: options,
            pool: AnimatedImageFramePool(),
            power: AnimatedImagePowerMonitor(isThrottling: false)
        )
        var loops = 0
        player.onLoop = { [unowned player] _ in
            loops += 1
            if loops == 1000 {
                // Escape hatch: with nothing in memory the next frame is late,
                // which is the only thing that breaks the loop.
                player.store.removeAllFrames()
            }
        }
        player.play()
        await player.waitUntilFull()

        clock.tick(1.0 / 60)

        #expect(loops < 1000) // Actual: 1000 (the escape hatch); without it, a hang
    }
}

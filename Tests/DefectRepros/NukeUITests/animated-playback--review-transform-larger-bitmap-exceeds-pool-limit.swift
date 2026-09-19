// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

// SUSPECTED BUG: a frame transform that returns a larger bitmap than the frame
// it was handed makes `AnimatedImageFramePool` hold several times its
// `costLimit`, and nothing ever gives the difference back.
//
// The pool divides its budget by what the frames are *estimated* to cost –
// `AnimatedImageFrameStore.bytesPerFrame`, worked out from the source's canvas
// (Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:153, `demand`
// at :253) – and decides from that estimate that the animation fits whole.
// The store then charges each frame what its bitmap actually occupies
// (`didDecode`, :477, "a transform that drew into a bitmap of its own
// included"), so `totalCost` is the real figure. `reclaimIfNeeded()`
// (AnimatedImageFramePool.swift:353) does notice `totalCost > costLimit`, but
// the only live store's window covers the whole animation, so `reclaim()` ->
// `evict()` drops nothing, and the pool stays over its limit for as long as
// the animation plays.
//
// `costLimit` is documented as "The memory the decoded frames of every player
// may occupy, in bytes", and `AnimatedImageFrameTransform`'s docs put no limit
// on what a transform may return (padding, a border, a wider pixel format, a
// higher-resolution redraw).
//
// Expected: `pool.totalCost <= pool.costLimit` once the window is full – the
//           animation is played out of a window, or the division uses what
//           the frames really cost.
// Actual:   `pool.totalCost == 4 * pool.costLimit`, and the player reports
//           itself fully buffered.

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedImageFramePoolTransformCostBugTests {
    @Test func aTransformThatDrawsALargerBitmapStaysInsideTheLimit() async throws {
        // GIVEN a pool that fits exactly the four frames the animation is
        // estimated to cost
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4)))
        let pool = AnimatedImageFramePool(costLimit: 4 * source.bytesPerFrame)

        // WHEN a transform draws every frame at twice the size
        var options = AnimatedImagePlayer.Options()
        options.frameTransform = AnimatedImageFrameTransform(identifier: "doubled") { image in
            let context = CGContext(
                data: nil,
                width: image.width * 2,
                height: image.height * 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width * 2, height: image.height * 2))
            return context?.makeImage()
        }
        let player = AnimatedImagePlayer(
            source: source,
            options: options,
            clock: ManualClock(),
            pool: pool,
            power: AnimatedImagePowerMonitor(isThrottling: false)
        )
        player.play()
        await player.waitUntilFull()

        // THEN the frames still fit in the pool
        #expect(pool.totalCost <= pool.costLimit) // Actual: 4 * costLimit
        #expect(player.diagnostics.bufferedByteCount <= player.diagnostics.bufferByteLimit) // Actual: 4x over
    }
}

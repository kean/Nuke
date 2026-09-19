// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

// BUG: A store whose last player is released while a decode is landing drops
// every frame it holds.
//
// `AnimatedImageFrameStore.didDecode(_:at:duration:)` ends with
// `evict(memberWindows())`. `evict` only leaves an idle store alone when
// `members.isEmpty`, but a released player's `Member` entry (a nil weak ref)
// stays in `members` until the pool sweeps on the next turn (the `deinit` can
// only call `setNeedsRebalance()`). When the decode's continuation runs before
// that sweep – the decode finished while the main thread was busy releasing
// cells, say – `members` is non-empty, `memberWindows()` is empty, and every
// frame "not covered by any window" is evicted: all of them, including the
// one just decoded.
//
// Expected (docs, AnimatedImages.md › Sharing): "The frames outlive the
// players holding them: a cell that scrolls off screen and comes back finds
// them still in memory." `evict` itself says "An idle store keeps everything
// for a view that comes back on screen".
//
// Actual: the store is left with zero frames and a view that comes back
// decodes the whole animation again.
//
// The decoder here is isolated to the main actor (which the
// `AnimatedImageFrameDecoding` docs allow) so that the player can be released
// inside the very job that delivers the frame, which makes the ordering
// deterministic. In an app the same ordering happens whenever the decode's
// continuation is already queued on the main actor when the player goes.
//
// Source: Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:376 and :486

@MainActor
private final class AnimatedFramesViewHookedDecoder: AnimatedImageFrameDecoding {
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<Int> = []
    private(set) var startedCount = 0

    /// Called with the index of a frame just before the frame is returned.
    var willReturn: ((Int) -> Void)?

    func decode(at index: Int) async -> CGImage? {
        startedCount += 1
        if released.remove(index) == nil {
            await withCheckedContinuation { gates[index] = $0 }
        }
        willReturn?(index)
        let context = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(red: CGFloat(index) / 4, green: 0, blue: 0, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return context?.makeImage()
    }

    func release(_ index: Int) {
        if let gate = gates.removeValue(forKey: index) {
            gate.resume()
        } else {
            released.insert(index)
        }
    }
}

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedFramesViewReleaseDuringDecodeBugTests {
    @MainActor private final class Box {
        var player: AnimatedImagePlayer?
    }

    @Test func theFramesOutliveAPlayerReleasedWhileAFrameIsLanding() async throws {
        let pool = AnimatedImageFramePool()
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4, size: CGSize(width: 32, height: 32))))
        let decoder = AnimatedFramesViewHookedDecoder()
        let box = Box()
        box.player = AnimatedImagePlayer(source: source, options: .init(), clock: ManualClock(), pool: pool, decoder: decoder)
        box.player?.play()
        let store = try #require(box.player?.store)
        decoder.release(0)
        decoder.release(1)
        decoder.release(2)
        for _ in 0..<100 where decoder.startedCount < 4 { await Task.yield() }
        #expect(store.decodedFrameCount(in: 0..<4) == 3)
        let decode = try #require(store.currentDecode)

        // The cell goes away just as the last frame lands.
        decoder.willReturn = { index in
            if index == 3 { box.player = nil }
        }
        decoder.release(3)
        await decode.value
        for _ in 0..<10 { await Task.yield() } // The division the release asked for

        #expect(pool.playerCount == 0)
        #expect(store.decodedFrameCount(in: 0..<4) == 4) // FAILS: 0
        #expect(pool.totalCost == 4 * 32 * 32 * 4) // FAILS: 0
    }
}

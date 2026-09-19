// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// BUG: A player that joins a store which already holds the frame at its
// playhead never displays that frame.
//
// `AnimatedImagePlayer.display(frameAt:)` is only reached from `seek`, `tick`
// and `frameDidDecode`. `frameDidDecode` is only called by the store for a
// frame that was *decoded while the player was waiting for it*. A player that
// joins a store where the frame at its `currentFrameIndex` is already decoded
// (another view of the same animation played it, or a cell scrolled back and
// got a new player) is never offered that frame: `store.add(_:)` finds nothing
// pending and schedules nothing, and nothing else displays it.
//
// Expected: `player.image` is the frame at `currentFrameIndex` as soon as that
// frame is in memory ("The image of the current frame, or `nil` until the
// first frame is decoded"). An `AnimatedImageView` with `isPlaybackEnabled =
// false` shows its first frame ("The first frame is displayed").
//
// Actual: `player.image` stays `nil`. A playing view is blank (or shows the
// poster) until the first tick moves the playhead to the *next* frame, so the
// frame the player joined on is never shown; a view held still
// (`isPlaybackEnabled = false`, e.g. Accessibility › Auto-Play Animated Images
// off) stays blank forever when it has no poster.
//
// Source: Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:137-145
// (init joins the store without displaying the frame it already holds) and
// Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:173-179 (`add`).

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedFramesViewJoiningPlayerBugTests {
    @Test func aPlayerJoiningDecodedFramesShowsTheFrameItIsOn() async throws {
        let pool = AnimatedImageFramePool()
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4)))
        let first = AnimatedImagePlayer(source: source, options: .init(), clock: ManualClock(), pool: pool)
        await first.waitUntilFull()
        #expect(first.image != nil)

        let second = AnimatedImagePlayer(source: source, options: .init(), clock: ManualClock(), pool: pool)
        await second.waitUntilFull()

        #expect(second.isFrameBuffered(second.currentFrameIndex)) // Passes: the frame is in memory
        #expect(second.image != nil) // FAILS: it is never displayed
    }

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
    @Test func aViewHeldStillShowsTheFirstFrameAnotherViewAlreadyDecoded() async throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4)))
        let other = AnimatedImagePlayer(source: source)
        await other.waitUntilFull()
        #expect(other.image != nil)

        let view = AnimatedImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        view.isPlaybackEnabled = false
        view.animatedImage = source
        let player = try #require(view.player)
        await player.waitUntilFull()

        #expect(view.image != nil) // FAILS: the view is blank, and stays blank
    }
#endif
}

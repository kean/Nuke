// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// BUG: A player shown by two views drives only the one it was handed last –
// and once that view is gone, the other one stays frozen for good.
//
// `AnimatedImageView.player.didSet` installs the view's frame handler in the
// player's single `onFrameForDisplay` slot, replacing whatever view had it.
// The view that lost the slot is never told; it goes on holding the player,
// and re-assigning the same player is a no-op (`guard oldValue !== player`),
// so nothing ever puts it back. When the second view is deallocated its
// handler (`[weak self]`) turns into a no-op, and the first view – still on
// screen, still holding the player – never shows another frame.
//
// The case: a model-owned player shown in a list row and in a detail screen
// (`AnimatedImage(player:)` in both, or `imageView.player = player` twice).
// Popping the detail leaves the row frozen on whatever frame it had when the
// detail appeared, while the player keeps playing. The docs present the
// player as the way to "control playback from outside the view" and say
// "Both views take one", with nothing restricting a player to one view.
//
// Expected: a view whose `player` is `p` shows `p`'s frames.
// Actual: it shows the frame it had when another view was handed `p`.
//
// Source: Sources/NukeUI/AnimatedImages/AnimatedImageView.swift:58-80
// (single `onFrameForDisplay` slot, replaced without the first view knowing)

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedFramesViewSharedPlayerBugTests {
    @Test func aViewKeepsShowingThePlayerItHoldsAfterAnotherViewOfItGoes() async throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4)))
        let player = AnimatedImagePlayer(source: source)
        await player.waitUntilFull()
        let row = AnimatedImageView()
        row.player = player
        #expect(row.image === player.image)

        var detail: AnimatedImageView? = AnimatedImageView()
        detail?.player = player
        detail = nil // The detail screen is dismissed
        #expect(detail == nil)
        row.player = player // What SwiftUI's next update of the row does

        player.seek(toFrame: 1)

        #expect(row.player === player)
        #expect(player.image != nil)
        #expect(row.image === player.image) // FAILS: the row is stuck on frame 0
    }
}

#endif

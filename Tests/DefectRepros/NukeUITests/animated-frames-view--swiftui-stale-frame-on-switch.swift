// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import SwiftUI
import Testing
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

// BUG: When SwiftUI reconfigures an `AnimatedImage` with a different animation
// and a poster, the view keeps showing the *previous* animation's frame
// instead of the new poster until the new animation's first frame is decoded.
//
// `AnimatedImageRepresentable.update(_:)` applies the poster only
// `if let poster, view.player?.image == nil` – and it checks that *before*
// switching the view to the new animation, so `view.player` is still the old
// player, whose `image` is the frame on screen. The poster is skipped; the
// new player has no image yet and `AnimatedImageView.player.didSet` only
// replaces the image when the new player has one, so the old animation's frame
// stays up. (On UIKit the new player also inherits the old frame's scale
// rather than the new poster's, since the scale is read from `view.image`.)
//
// `AnimatedImageView.display(_:)`, the UIKit path, does this in the right
// order (animation first, then the poster if there is no frame yet).
//
// Expected (`AnimatedImage.init(_:poster:)` docs): the poster is "the still
// frame to show until the first frame of the animation is decoded".
//
// Actual: `view.image` is the last frame of the animation the view was
// showing before – a different picture entirely (a row reused for another
// message, a LazyImage whose URL changed).
//
// Source: Sources/NukeUI/AnimatedImages/AnimatedImage.swift:216-227

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedFramesViewStaleFrameOnSwitchBugTests {
    @Test func showsTheNewPosterRatherThanTheOldAnimationsFrame() async throws {
        let (old, _) = AnimatedImageTest.makePlayer(frameCount: 4)
        await old.waitUntilFull()
        #expect(old.image != nil)
        // A decoder held open, so the new animation's first frame never
        // arrives and only its poster can hold the place.
        let (new, _, _) = AnimatedImageTest.makeGatedPlayer(frameCount: 4)
        let oldPoster = Test.image
        let newPoster = Test.image
        #expect(newPoster !== oldPoster)

        let host = ViewHost(old) { player in
            AnimatedImage(player: player, poster: player === old ? oldPoster : newPoster)
        }
        await host.render(until: { host.firstView(ofType: AnimatedImageView.self)?.image === old.image })
        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        #expect(view.image === old.image)

        await host.update(new, until: { view.player === new })
        #expect(view.player === new)
        #expect(new.image == nil)

        #expect(view.image !== old.image) // FAILS: still the old animation's frame
        #expect(view.image === newPoster) // FAILS
    }
}

#endif

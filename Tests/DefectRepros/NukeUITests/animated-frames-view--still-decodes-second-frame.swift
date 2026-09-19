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

// DOCS-VS-BEHAVIOR: AnimatedImages.md › Controlling Playback says of
// `AnimatedImageView.isPlaybackEnabled = false`: "The first frame is displayed
// and no frames beyond it are ever decoded."
//
// A player that never plays asks for `AnimatedImagePlayer.idleFrameCount` (2)
// frames – the floor every player holds ("with one frame, the next could only
// start decoding after the current one was dropped") – so the second frame is
// decoded too. Either the article or the floor for a player that is never
// going to play is wrong; the code comments make the floor deliberate, so the
// article is the likely fix ("no frames beyond the first two").
//
// Expected (docs): frame 1 is never decoded.
// Actual: frame 1 is decoded and held.
//
// Source: Documentation/NukeUI.docc/AnimatedImages.md ("no frames beyond it
// are ever decoded") vs Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:263-268

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedFramesViewStillDecodesBugTests {
    @Test func anAnimationHeldStillDecodesNothingPastItsFirstFrame() async throws {
        let view = AnimatedImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        view.isPlaybackEnabled = false
        view.animatedImage = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 8)))
        let player = try #require(view.player)

        await player.waitUntilFull()

        #expect(view.image != nil)
        #expect(player.isFrameBuffered(0))
        #expect(player.isFrameBuffered(1) == false) // FAILS: the second frame was decoded
        #expect(player.diagnostics.decodedFrameCount == 1) // FAILS: 2
    }
}

#endif

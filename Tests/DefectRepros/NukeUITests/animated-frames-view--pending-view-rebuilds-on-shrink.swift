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

// BUG: An `AnimatedImageView` given its animation before its first layout
// (every cell, every SwiftUI `AnimatedImage`) rebuilds its player when it
// shrinks, if the animation fitted the view at that first layout. At the first
// layout `applyAutomaticDownsamplingIfNeeded()` clamps the derived size to
// `nil` (the animation already fits) and then records the animation as still
// pending (`sourcePendingDownsampling = maxPixelSize == nil ? source : nil`).
// The next, smaller layout goes down the pending branch and builds a new,
// downsampled player.
//
// Verified variant of the original repro. The original shrank 200x200 -> 20x20,
// which does replace the player, but the replacement (maxPixelSize 64) joins
// the existing full-size 100 px store through the pool's `largerStore` reuse
// (64...128 covers 100), so no frames are decoded twice there. Shrinking to
// 10x10 (derived 32 px, reuse limit 64 < 100) shows the claimed second set of
// frames and second decode.
//
// Source: Sources/NukeUI/AnimatedImages/AnimatedImageView.swift:263-284

@Suite(.timeLimit(.minutes(1))) @MainActor
struct AnimatedFramesViewPendingShrinkBugTests {
    private func layOut(_ view: AnimatedImageView, _ size: CGSize) {
        view.frame = CGRect(origin: .zero, size: size)
#if os(macOS)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
#else
        view.setNeedsLayout()
        view.layoutIfNeeded()
#endif
    }

    @Test func aViewThatShrinksKeepsItsPlayerWhateverCameFirst() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4, size: CGSize(width: 100, height: 100))))

        // Laid out first, then handed the animation: keeps its player.
        let laidOutFirst = AnimatedImageView()
        layOut(laidOutFirst, CGSize(width: 200, height: 200))
        laidOutFirst.animatedImage = source
        let kept = try #require(laidOutFirst.player)
        layOut(laidOutFirst, CGSize(width: 20, height: 20))
        #expect(laidOutFirst.player === kept) // Passes

        // Handed the animation first, then laid out.
        let imageFirst = AnimatedImageView()
        imageFirst.animatedImage = source
        layOut(imageFirst, CGSize(width: 200, height: 200))
        let player = try #require(imageFirst.player)
        #expect(player.options.maxPixelSize == nil) // Fits: decoded whole

        layOut(imageFirst, CGSize(width: 20, height: 20))
        #expect(imageFirst.player === player) // FAILS: rebuilt at maxPixelSize 64 (same store though)
    }

    @Test func aViewThatShrinksKeepsItsFramesWhateverCameFirst() throws {
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4, size: CGSize(width: 100, height: 100))))

        let laidOutFirst = AnimatedImageView()
        layOut(laidOutFirst, CGSize(width: 200, height: 200))
        laidOutFirst.animatedImage = source
        let kept = try #require(laidOutFirst.player)
        layOut(laidOutFirst, CGSize(width: 10, height: 10))
        #expect(laidOutFirst.player === kept) // Passes
        #expect(laidOutFirst.player?.store === kept.store) // Passes

        let imageFirst = AnimatedImageView()
        imageFirst.animatedImage = source
        layOut(imageFirst, CGSize(width: 200, height: 200))
        let player = try #require(imageFirst.player)
        let store = player.store

        layOut(imageFirst, CGSize(width: 10, height: 10))

        #expect(imageFirst.player === player) // FAILS
        #expect(imageFirst.player?.store === store) // FAILS: a second set of frames at 32 px
    }
}

#endif

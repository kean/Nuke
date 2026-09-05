// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import SwiftUI
import Testing
@testable import NukeUI

/// Covers the size ``AnimatedImage`` reports, which is what makes it lay out
/// like an `Image` rather than like a box that happens to contain one.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageLayoutTests {
    private let wide = CGSize(width: 200, height: 100)

    @Test func takesItsNaturalSizeUntilItIsResizable() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: 50, height: 50),
            source: wide,
            isResizable: false
        )

        #expect(size == wide)
    }

    @Test func fitsInsideWhatItIsOffered() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: 100, height: 100),
            source: wide,
            isResizable: true
        )

        // The size the frames occupy, not the square they were offered, so that
        // a background or a clip shape wraps the animation – the same thing
        // `Image.resizable().scaledToFit()` reports.
        #expect(size == CGSize(width: 100, height: 50))
    }

    @Test func returnsWhatScaledToFillProposes() {
        // `scaledToFill()` is what covers a box: for a square box it proposes
        // the 200×100 that covers it, which already matches the animation, so
        // there is nothing left to fit and this hands the proposal back. The
        // parent clips what hangs over the edge.
        let size = animatedImageSize(
            for: ProposedViewSize(width: 200, height: 100),
            source: wide,
            isResizable: true
        )

        #expect(size == CGSize(width: 200, height: 100))
    }

    @Test func derivesTheOtherSideFromTheAspectRatio() {
        let width = animatedImageSize(
            for: ProposedViewSize(width: 50, height: nil),
            source: wide,
            isResizable: true
        )
        let height = animatedImageSize(
            for: ProposedViewSize(width: nil, height: 50),
            source: wide,
            isResizable: true
        )

        #expect(width == CGSize(width: 50, height: 25))
        #expect(height == CGSize(width: 100, height: 50))
    }

    @Test func takesItsNaturalSizeWhenNothingIsProposed() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: nil, height: nil),
            source: wide,
            isResizable: true
        )

        #expect(size == wide)
    }

    @Test func fallsBackToTheNaturalSizeForAnUnboundedProposal() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: .infinity, height: .infinity),
            source: wide,
            isResizable: true
        )

        #expect(size == wide)
    }

    @Test func takesItsNaturalSizeInPointsRatherThanInPixels() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: 500, height: 500),
            source: wide,
            scale: 2,
            isResizable: false
        )

        // An animation is measured in pixels and laid out in points, the way
        // `Image` lays out the still the decoder produced beside it.
        #expect(size == CGSize(width: 100, height: 50))
    }

    @Test func fitsTheScaledSizeInsideWhatItIsOffered() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: 50, height: 50),
            source: wide,
            scale: 2,
            isResizable: true
        )

        #expect(size == CGSize(width: 50, height: 25))
    }

    @Test func hasNoSizeOfItsOwnWhenTheAnimationHasNone() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: 100, height: 100),
            source: .zero,
            isResizable: true
        )

        #expect(size == nil)
    }
}

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

/// Covers the other half of laying out like an `Image`: what the platform view
/// does with the frames once the size is settled.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageContentModeTests {
    @Test func fitsTheFramesInsideTheSizeItWasGiven() async throws {
        // The view is sized to the animation's aspect ratio, so fitting the
        // frames inside it is what covers it: `scaledToFill()` is a larger box
        // to fit them into, not a different content mode.
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        let host = ViewHost(false) { isFilling in
            if isFilling {
                AnimatedImage(source).resizable().scaledToFill()
            } else {
                AnimatedImage(source).resizable()
            }
        }
        await host.render(until: { host.firstView(ofType: AnimatedImageView.self) != nil })
        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        #expect(fitsTheFrames(view))

        await host.update(true)

        #expect(fitsTheFrames(view))
    }

    private func fitsTheFrames(_ view: AnimatedImageView) -> Bool {
#if os(macOS)
        view.imageScaling == .scaleProportionallyUpOrDown
#else
        view.contentMode == .scaleAspectFit
#endif
    }
}

#endif

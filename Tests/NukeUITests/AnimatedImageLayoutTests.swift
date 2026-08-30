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
            isResizable: false,
            contentMode: .fit
        )

        #expect(size == wide)
    }

    @Test func fitsInsideWhatItIsOffered() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: 100, height: 100),
            source: wide,
            isResizable: true,
            contentMode: .fit
        )

        // The size the frames occupy, not the square they were offered, so that
        // a background or a clip shape wraps the animation – the same thing
        // `Image.resizable().scaledToFit()` reports.
        #expect(size == CGSize(width: 100, height: 50))
    }

    @Test func coversWhatItIsOfferedWhenItFills() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: 100, height: 100),
            source: wide,
            isResizable: true,
            contentMode: .fill
        )

        // The view clips what hangs over the edge.
        #expect(size == CGSize(width: 100, height: 100))
    }

    @Test func derivesTheOtherSideFromTheAspectRatio() {
        let width = animatedImageSize(
            for: ProposedViewSize(width: 50, height: nil),
            source: wide,
            isResizable: true,
            contentMode: .fit
        )
        let height = animatedImageSize(
            for: ProposedViewSize(width: nil, height: 50),
            source: wide,
            isResizable: true,
            contentMode: .fit
        )

        #expect(width == CGSize(width: 50, height: 25))
        #expect(height == CGSize(width: 100, height: 50))
    }

    @Test func takesItsNaturalSizeWhenNothingIsProposed() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: nil, height: nil),
            source: wide,
            isResizable: true,
            contentMode: .fit
        )

        #expect(size == wide)
    }

    @Test func fallsBackToTheNaturalSizeForAnUnboundedProposal() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: .infinity, height: .infinity),
            source: wide,
            isResizable: true,
            contentMode: .fit
        )

        #expect(size == wide)
    }

    @Test func hasNoSizeOfItsOwnWhenTheAnimationHasNone() {
        let size = animatedImageSize(
            for: ProposedViewSize(width: 100, height: 100),
            source: .zero,
            isResizable: true,
            contentMode: .fit
        )

        #expect(size == nil)
    }
}

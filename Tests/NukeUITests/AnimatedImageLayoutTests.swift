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

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

/// Covers the other half of laying out like an `Image`: the content mode, which
/// the platform view applies to the frames once the size is settled.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImageContentModeTests {
    @Test func followsAContentModeThatChanges() async throws {
        // SwiftUI reuses the view across updates, so a content mode read only
        // when the view is created is the one it keeps for good.
        let source = try #require(AnimatedImageSource(data: Test.animatedGIF()))
        let host = ViewHost(ContentMode.fit) { contentMode in
            AnimatedImage(source).resizable(contentMode: contentMode)
        }
        await host.render(until: { host.firstView(ofType: AnimatedImageView.self) != nil })
        let view = try #require(host.firstView(ofType: AnimatedImageView.self))
        #expect(scaling(of: view) == .fit)

        await host.update(.fill)

        #expect(scaling(of: view) == .fill)
    }

    private func scaling(of view: AnimatedImageView) -> ContentMode? {
#if os(macOS)
        // `imageScaling` only ever fits, so `.fill` is the view's own drawing.
        view.isAspectFillEnabled ? .fill : .fit
#else
        switch view.contentMode {
        case .scaleAspectFit: .fit
        case .scaleAspectFill: .fill
        default: nil
        }
#endif
    }
}

#endif

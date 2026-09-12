// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke
@testable import NukeUI

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Suite(.timeLimit(.minutes(1))) @MainActor
struct PlatformViewLayoutTests {

    // MARK: - pinToSuperview

    @Test func pinToSuperviewCreatesFourConstraints() {
        let superview = _PlatformBaseView()
        let view = _PlatformBaseView()
        superview.addSubview(view)

        let constraints = view.pinToSuperview()

        #expect(constraints.count == 4)
        #expect(constraints.allSatisfy { $0.isActive })
        #expect(!view.translatesAutoresizingMaskIntoConstraints)
    }

    @Test func pinToSuperviewWithoutSuperviewCreatesNoConstraints() {
        let view = _PlatformBaseView()
        #expect(view.pinToSuperview().isEmpty)
    }

    // MARK: - centerInSuperview

    @Test func centerInSuperviewCreatesTwoConstraints() {
        let superview = _PlatformBaseView()
        let view = _PlatformBaseView()
        superview.addSubview(view)

        let constraints = view.centerInSuperview()

        #expect(constraints.count == 2)
        #expect(constraints.allSatisfy { $0.isActive })
        #expect(!view.translatesAutoresizingMaskIntoConstraints)
    }

    @Test func centerInSuperviewWithoutSuperviewCreatesNoConstraints() {
        let view = _PlatformBaseView()
        #expect(view.centerInSuperview().isEmpty)
    }

    // MARK: - layout(with:)

    @Test func layoutWithFillPinsToSuperview() {
        let superview = _PlatformBaseView()
        let view = _PlatformBaseView()
        superview.addSubview(view)

        #expect(view.layout(with: .fill).count == 4)
    }

    @Test func layoutWithCenterCentersInSuperview() {
        let superview = _PlatformBaseView()
        let view = _PlatformBaseView()
        superview.addSubview(view)

        #expect(view.layout(with: .center).count == 2)
    }

    // MARK: - animateOpacity

    @Test func animateOpacityAddsAnimation() throws {
        let layer = CALayer()
        layer.animateOpacity(duration: 0.5)

        let animation = try #require(layer.animation(forKey: "imageTransition") as? CABasicAnimation)
        #expect(animation.keyPath == "opacity")
        #expect(animation.duration == 0.5)
        #expect(animation.fromValue as? Int == 0)
        #expect(animation.toValue as? Int == 1)
    }
}

#endif

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

// BUG: the `.fadeIn` transition of `loadImage(with:options:into:)` overwrites
// the image view's `alpha` with `1` when it cross-dissolves between content
// modes.
//
// Sources/NukeUI/ImageViewExtensions.swift, `runCrossDissolveWithContentMode`:
//
//     transitionView.alpha = 1
//     imageView.alpha = 0
//     imageView.nuke_display(image)
//     UIView.animate(...) {
//         transitionView.alpha = 0
//         imageView.alpha = 1
//     }
//
// Expected: the transition only animates between the two images; a view the
// app dimmed (e.g. `alpha = 0.5` for a disabled cell) keeps its alpha, as it
// does with the regular `.fadeIn` path (`UIView.transition` with
// `.transitionCrossDissolve`, used when the content mode doesn't change) and
// when there is no transition at all.
//
// Actual: the view ends up fully opaque (`alpha == 1`), and the temporary view
// showing the previous image is also drawn at full opacity, so a dimmed image
// flashes bright during the transition. Whether the app's alpha survives
// depends on whether `contentModes` differ between the placeholder/previous
// state and the success state.

@Suite(.timeLimit(.minutes(5))) @MainActor
struct ImageViewCrossDissolveAlphaRepro {
    @Test func crossDissolvePreservesImageViewAlpha() async {
        // Given a dimmed image view in a window displaying an image with a
        // content mode different from the one used for the loaded image
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.isHidden = false
        let imageView = UIImageView(frame: window.bounds)
        window.addSubview(imageView)
        imageView.image = Test.image
        imageView.contentMode = .center
        imageView.alpha = 0.5

        var options = ImageLoadingOptions()
        options.pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        options.transition = .fadeIn(duration: 0.1)
        options.isPrepareForReuseEnabled = false
        options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .center)

        // When
        let expectation = TestExpectation()
        NukeUI.loadImage(with: Test.request, options: options, into: imageView) { _ in
            expectation.fulfill()
        }
        await expectation.wait()

        // Then
        #expect(imageView.image != nil)
        #expect(imageView.alpha == 0.5) // FAILS: 1.0
        withExtendedLifetime(window) {}
    }

    @Test func simpleFadeInPreservesImageViewAlpha() async {
        // The same setup without a content mode change takes the regular
        // path, which leaves the alpha alone (passes; shown for contrast).
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.isHidden = false
        let imageView = UIImageView(frame: window.bounds)
        window.addSubview(imageView)
        imageView.image = Test.image
        imageView.contentMode = .scaleAspectFill
        imageView.alpha = 0.5

        var options = ImageLoadingOptions()
        options.pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        options.transition = .fadeIn(duration: 0.1)
        options.isPrepareForReuseEnabled = false
        options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .center)

        let expectation = TestExpectation()
        NukeUI.loadImage(with: Test.request, options: options, into: imageView) { _ in
            expectation.fulfill()
        }
        await expectation.wait()

        #expect(imageView.alpha == 0.5)
        withExtendedLifetime(window) {}
    }
}

#endif

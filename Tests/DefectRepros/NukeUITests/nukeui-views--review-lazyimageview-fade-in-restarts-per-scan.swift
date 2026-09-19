// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// BUG: `LazyImageView`'s `.fadeIn` transition fades the image view in from
// fully transparent again for every progressive scan and for the final image,
// although an image is already on screen.
//
// Sources/NukeUI/LazyImageView.swift:
//
//     private func handle(preview: ImageResponse) {
//         ...
//         display(preview.container, isFromMemory: false)   // every scan
//     }
//
//     private func display(_ container: ImageContainer, isFromMemory: Bool) {
//         ...
//         if !isFromMemory, let transition = transition {
//             runTransition(transition, container)          // no "already visible" check
//         }
//     }
//
//     // iOS                                  // macOS
//     imageView.alpha = 0                     imageView.layer?.animateOpacity(duration:)
//     UIView.animate { imageView.alpha = 1 }  // CABasicAnimation opacity 0 -> 1
//
// Expected: the transition brings the image in once; a better scan of the
// image that is already displayed, or the final image replacing it, is swapped
// in place (as `loadImage(with:options:into:)` does on iOS, where `.fadeIn` is
// a cross-dissolve from the current content).
//
// Actual: with progressive decoding on, each scan and then the final image
// makes the visible image disappear and fade back in over `duration` (0.33 s by
// default) – a flicker on every scan. The same happens with
// `isResetEnabled == false`, where the previous image is cut to transparent
// instead of being cross-faded.

@Suite(.timeLimit(.minutes(5))) @MainActor
struct LazyImageViewFadeInRestartsRepro {
    @Test func fadeInIsNotRestartedOnceAnImageIsOnScreen() async {
        // Given a progressive load with the fade-in transition
        let loader = MockProgressiveDataLoader()
        let view = LazyImageView()
        view.pipeline = ImagePipeline {
            $0.dataLoader = loader
            $0.imageCache = nil
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
            $0.imageProcessingQueue.maxConcurrentTaskCount = 1
        }
        view.transition = .fadeIn(duration: 10)
#if os(macOS)
        view.imageView.wantsLayer = true
#else
        // UIKit only runs animations for views in a window.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        view.frame = window.bounds
        window.addSubview(view)
        window.isHidden = false
#endif

        var previewCount = 0
        var restartedFades: [String] = []
        view.onPreview = { _ in
            previewCount += 1
            if previewCount > 1, fadeInAnimation(of: view) != nil {
                restartedFades.append("preview \(previewCount)")
            }
            // Let the fade-in of the image on screen finish.
            removeAnimations(of: view)
            loader.resume()
        }
        let expectation = TestExpectation()
        view.onCompletion = { _ in
            if fadeInAnimation(of: view) != nil {
                restartedFades.append("final")
            }
            expectation.fulfill()
        }

        // When
        view.url = Test.url
        await expectation.wait()

        // Then
        #expect(previewCount > 0) // An image was on screen before the final one
        #expect(restartedFades.isEmpty) // FAILS: ["preview 2", "final"]
#if !os(macOS)
        withExtendedLifetime(window) {}
#endif
    }
}

@MainActor
private func fadeInAnimation(of view: LazyImageView) -> CAAnimation? {
#if os(macOS)
    view.imageView.layer?.animation(forKey: "imageTransition")
#else
    view.imageView.layer.animation(forKey: "opacity")
#endif
}

@MainActor
private func removeAnimations(of view: LazyImageView) {
#if os(macOS)
    view.imageView.layer?.removeAllAnimations()
#else
    view.imageView.layer.removeAllAnimations()
#endif
}

#endif

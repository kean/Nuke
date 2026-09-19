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

// BUG: `LazyImageView` keeps the previous image visible in its built-in
// `imageView` when the next response is displayed by a view from
// `makeImageView`, as long as that response doesn't go through the regular
// reset: a memory cache hit, or any response with `isResetEnabled == false`.
//
// Sources/NukeUI/LazyImageView.swift:
// - `load(_:)` handles a cache hit with `resetOrDefer(clearImage: false)` so
//   that the hit "can overwrite `imageView.image` directly" (line ~297-300);
// - the deferred reset in `display(_:isFromMemory:)` also uses
//   `clearImage: false` (line ~369);
// - but when `makeImageView` returns a view, `display` adds that view on top
//   and never touches `imageView`, so nothing overwrites or hides it.
//
// Expected: once a response is displayed by a custom view, the built-in image
// view is hidden and doesn't hold on to the previous image – exactly what
// happens for a regular network response (`imageView` is hidden by
// `reset(clearImage: true)`, and `fadeInTransitionSkippedWhenImageViewIsUnused`
// relies on it).
//
// Actual: `imageView` stays visible with the previous image under the custom
// view. The typical setup – `makeImageView` returning a view only for some
// content types (the documented "return nil to use the default platform image
// view") – shows the stale image from the previous cell through any
// transparent part of the custom view, and retains it.

@Suite(.timeLimit(.minutes(5))) @MainActor
struct LazyImageViewStaleImageUnderCustomViewRepro {
    let pipeline: ImagePipeline
    let view: LazyImageView
    let otherRequest = ImageRequest(url: URL(string: "https://example.com/other.jpg")!)

    init() {
        pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = MockImageCache()
        }
        view = LazyImageView()
        view.pipeline = pipeline
        view.transition = nil
    }

    @Test func memoryCacheHitDisplayedByCustomViewHidesPreviousImage() async {
        // Given a view displaying an image in its built-in image view
        await load(Test.request)
        #expect(!view.imageView.isHidden)

        // When the next image is a memory cache hit displayed by a custom view
        pipeline.cache[otherRequest] = Test.container
        let customView = _PlatformBaseView()
        view.makeImageView = { _ in customView }
        view.request = otherRequest

        // Then
        #expect(customView.superview === view)
        #expect(view.imageView.isHidden) // FAILS: still visible
        #expect(view.imageView.image == nil) // FAILS: still the previous image
    }

    @Test func deferredResetForCustomViewHidesPreviousImage() async {
        // Given a view displaying an image in its built-in image view
        await load(Test.request)
        #expect(!view.imageView.isHidden)

        // When the next image, loaded with the reset deferred, is displayed by
        // a custom view
        view.isResetEnabled = false
        let customView = _PlatformBaseView()
        view.makeImageView = { _ in customView }
        await load(otherRequest)

        // Then
        #expect(customView.superview === view)
        #expect(view.imageView.isHidden) // FAILS: still visible
        #expect(view.imageView.image == nil) // FAILS: still the previous image
    }

    private func load(_ request: ImageRequest) async {
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.request = request
        await expectation.wait()
        view.onCompletion = nil
    }
}

#endif

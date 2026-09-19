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

// BUG: `LazyImageView` decides whether a newly assigned placeholder or failure
// view is visible without looking at what the view is showing.
//
// Sources/NukeUI/LazyImageView.swift:
//
//     private func setPlaceholderView(_ oldView: _PlatformBaseView?, _ newView: _PlatformBaseView?) {
//         ...
//         newView.isHidden = !imageView.isHidden   // "no image on screen" == "loading"
//
//     private func setFailureView(_ oldView: _PlatformBaseView?, _ newView: _PlatformBaseView?) {
//         ...
//         newView.isHidden = true                  // always hidden, even mid-failure
//
// `imageView.isHidden` is `true` in every state where the built-in image view
// isn't used – after a failure, after `reset()`, and while a `makeImageView`
// view displays the image – so a placeholder assigned in any of those states
// is shown although nothing is loading. And a failure view assigned while the
// failure is on screen is never shown.
//
// Expected: the placeholder is "shown while the request is in progress" and the
// failure view is "shown if the request fails" (the property docs), regardless
// of when they are assigned. Picking the failure image from the error in
// `onFailure` (`view.failureImage = image(for: error)`) is a natural pattern,
// and `handle(result:)` calls `onFailure` after it has already un-hidden the
// previous failure view.
//
// Actual: the failure image assigned from `onFailure` stays hidden, so the view
// shows nothing; a placeholder assigned after a failure appears on top of the
// failure view (both visible); a placeholder assigned after a load displayed by
// a custom view appears under that view.

@Suite(.timeLimit(.minutes(5))) @MainActor
struct LazyImageViewLateSubviewVisibilityRepro {
    let dataLoader: MockDataLoader
    let view: LazyImageView

    init() {
        let dataLoader = MockDataLoader()
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        self.dataLoader = dataLoader
        view = LazyImageView()
        view.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        view.transition = nil
    }

    @Test func failureImageAssignedInOnFailureIsShown() async throws {
        // Given the failure image is chosen from the error
        let failureImage = Test.image
        view.onFailure = { [view] _ in view.failureImage = failureImage }

        // When
        await load(Test.url)

        // Then
        let failureView = try #require(view.failureView)
        #expect(!failureView.isHidden) // FAILS: hidden, nothing is displayed
    }

    @Test func placeholderAssignedAfterFailureIsHidden() async {
        // Given a view displaying a failure
        let failureView = _PlatformBaseView()
        view.failureView = failureView
        view.placeholderView = nil
        await load(Test.url)
        #expect(!failureView.isHidden)

        // When
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder

        // Then nothing is loading, and `showPlaceholderOnFailure` is off
        #expect(placeholder.isHidden) // FAILS: shown along with the failure view
    }

    @Test func placeholderAssignedWhileCustomViewDisplaysImageIsHidden() async {
        // Given an image displayed by a custom view
        let url = URL(string: "https://example.com/success.jpg")!
        let customView = _PlatformBaseView()
        view.makeImageView = { _ in customView }
        await load(url)
        #expect(customView.superview === view)

        // When
        let placeholder = _PlatformBaseView()
        view.placeholderView = placeholder

        // Then
        #expect(placeholder.isHidden) // FAILS: shown under the custom view
    }

    private func load(_ url: URL) async {
        let expectation = TestExpectation()
        view.onCompletion = { _ in expectation.fulfill() }
        view.url = url
        await expectation.wait()
        view.onCompletion = nil
    }
}

#endif

// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if !os(watchOS)

// BUG: `LazyImageView` delivers `onCompletion` for a request after the
// completion of the request that replaced it, when the replacement is started
// from `onSuccess`/`onFailure` and finishes synchronously (a memory cache hit
// or a `nil` request).
//
// Sources/NukeUI/LazyImageView.swift, `handle(result:isSync:)`:
//
//     imageTask = nil
//     switch result {
//     case .success(let response): onSuccess?(response)
//     case .failure(let error): onFailure?(error)   // app sets `view.url = fallback`
//     }
//     onCompletion?(result)                          // stale result, delivered last
//
// The common "show a fallback image on failure" pattern sets a new URL from
// `onFailure`. If the fallback is in the memory cache, `load(_:)` handles it
// synchronously – `onSuccess(fallback)` and `onCompletion(fallback)` run inside
// `onFailure` – and only then does the outer `handle` call
// `onCompletion(original failure)`.
//
// Expected: the completions arrive in the order the requests completed, so the
// last `onCompletion` describes what's on screen: [failure, success].
//
// Actual: [success, failure]. An app mirroring `onCompletion` into its state
// (an error badge, a retry button, analytics) ends up reporting a failure while
// the view displays the fallback image.

@Suite(.timeLimit(.minutes(5))) @MainActor
struct LazyImageViewSupersededCompletionOrderRepro {
    @Test func completionOfReplacedRequestIsNotDeliveredAfterReplacement() async {
        // Given a failing request, and a fallback image in the memory cache
        let dataLoader = MockDataLoader()
        dataLoader.results[Test.url] = .failure(NSError(domain: "test", code: 42))
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = MockImageCache()
        }
        let fallback = ImageRequest(url: URL(string: "https://example.com/fallback.jpg")!)
        pipeline.cache[fallback] = Test.container

        let view = LazyImageView()
        view.pipeline = pipeline
        view.transition = nil
        view.onFailure = { _ in view.request = fallback }

        var completions: [String] = []
        let expectation = TestExpectation()
        view.onCompletion = { result in
            completions.append(result.isSuccess ? "success" : "failure")
            if completions.count == 2 { expectation.fulfill() }
        }

        // When
        view.url = Test.url
        await expectation.wait()

        // Then
        #expect(view.imageView.image != nil) // The fallback is displayed
        #expect(completions == ["failure", "success"]) // FAILS: ["success", "failure"]
    }
}

#endif

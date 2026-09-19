// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@MainActor
func loadImageAndWait(
    with request: ImageRequest,
    options: ImageLoadingOptions? = nil,
    into imageView: ImageDisplayingView
) async {
    let expectation = TestExpectation()
    NukeUI.loadImage(
        with: request,
        options: options,
        into: imageView,
        completion: { _ in
            expectation.fulfill()
        })
    await expectation.wait()
}

@MainActor
func loadImageExpectingSuccess(
    with request: ImageRequest,
    options: ImageLoadingOptions? = nil,
    into imageView: ImageDisplayingView
) async {
    let expectation = TestExpectation()
    NukeUI.loadImage(
        with: request,
        options: options,
        into: imageView,
        completion: { result in
            #expect(result.isSuccess)
            expectation.fulfill()
        })
    await expectation.wait()
}

/// A request for `Test.url` whose processor stamps `id` on the image, so a
/// test can tell which of several requests produced what is on screen.
func request(id: String) -> ImageRequest {
    ImageRequest(url: Test.url, processors: [MockImageProcessor(id: id)])
}

/// Starts a request and keeps the main thread busy until the pipeline has
/// finished it, so that its response is dispatched but hasn't been handled.
@MainActor
func runWhileMainThreadIsBlocked(untilTaskCompletes observer: ImagePipelineObserver, _ action: () -> Void) throws {
    let semaphore = DispatchSemaphore(value: 0)
    let token = NotificationCenter.default.addObserver(forName: ImagePipelineObserver.didCompleteTask, object: observer, queue: nil) { _ in
        semaphore.signal()
    }
    defer { NotificationCenter.default.removeObserver(token) }
    action()
    try #require(semaphore.wait(timeout: .now() + 60) == .success)
}

#endif

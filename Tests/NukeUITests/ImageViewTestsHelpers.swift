// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

/// An image view, and a pipeline that loads into it from mocks: what the tests
/// of the image view extensions start with.
@MainActor
struct ImageViewFixture {
    let imageView = _ImageView()
    let observer = ImagePipelineObserver()
    let imageCache = MockImageCache()
    let dataLoader = MockDataLoader()
    let pipeline: ImagePipeline

    /// Options that load through ``pipeline``.
    let options: ImageLoadingOptions

    init() {
        let (observer, imageCache, dataLoader) = (self.observer, self.imageCache, self.dataLoader)
        self.pipeline = ImagePipeline(delegate: observer) {
            $0.dataLoader = dataLoader
            $0.imageCache = imageCache
        }
        var options = ImageLoadingOptions()
        options.pipeline = pipeline
        self.options = options
    }
}

#if os(iOS) || os(tvOS) || os(visionOS)
/// Puts the view in a container in a visible window, which is what makes UIKit
/// run the animations of a transition.
@MainActor
func hostInWindow(_ view: UIView) -> (window: UIWindow, container: UIView) {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    let container = UIView(frame: window.bounds)
    window.addSubview(container)
    window.isHidden = false
    container.addSubview(view)
    view.frame = container.bounds
    return (window, container)
}
#endif

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

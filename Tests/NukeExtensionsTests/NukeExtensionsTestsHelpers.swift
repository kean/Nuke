// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeExtensions

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@MainActor
func loadImageAndWait(
    with request: ImageRequest,
    options: ImageLoadingOptions? = nil,
    into imageView: ImageDisplayingView
) async {
    let expectation = TestExpectation()
    NukeExtensions.loadImage(
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
    NukeExtensions.loadImage(
        with: request,
        options: options,
        into: imageView,
        completion: { result in
            #expect(result.isSuccess)
            expectation.fulfill()
        })
    await expectation.wait()
}

#endif

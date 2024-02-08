// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke
@testable import NukeExtensions

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
extension XCTestCase {
    @MainActor
    func expectToFinishLoadingImage(with request: ImageRequest,
                                    options: ImageLoadingOptions = ImageLoadingOptions.shared,
                                    into imageView: ImageDisplayingView,
                                    completion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)? = nil) {
        let expectation = self.expectation(description: "Image loaded for \(request)")
        NukeExtensions.loadImage(
            with: request,
            options: options,
            into: imageView,
            completion: { result in
                XCTAssertTrue(Thread.isMainThread)
                completion?(result)
                expectation.fulfill()
        })
    }

    @MainActor
    func expectToLoadImage(with request: ImageRequest, options: ImageLoadingOptions = ImageLoadingOptions.shared, into imageView: ImageDisplayingView) {
        expectToFinishLoadingImage(with: request, options: options, into: imageView) { result in
            XCTAssertTrue(result.isSuccess)
        }
    }
}

extension ImageLoadingOptions {
    private static var stack = [ImageLoadingOptions]()

    static func pushShared(_ shared: ImageLoadingOptions) {
        stack.append(ImageLoadingOptions.shared)
        ImageLoadingOptions.shared = shared
    }

    static func popShared() {
        ImageLoadingOptions.shared = stack.removeLast()
    }
}
#endif

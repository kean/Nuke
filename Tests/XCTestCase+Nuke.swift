// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation
import Nuke

extension XCTestCase {
    func expect(_ pipeline: ImagePipeline) -> TestExpectationImagePipeline {
        return TestExpectationImagePipeline(test: self, pipeline: pipeline)
    }
}

struct TestExpectationImagePipeline {
    let test: XCTestCase
    let pipeline: ImagePipeline

    func toLoadImage(with request: ImageRequest, _ completion: ((ImageResponse?, ImagePipeline.Error?) -> Void)? = nil) {
        let expectation = test.expectation(description: "Image loaded for \(request)")
        pipeline.loadImage(with: request) { response, error in
            completion?(response, error)
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNotNil(response)
            expectation.fulfill()
        }
    }

    func toFail(with request: ImageRequest, _ completion: ((ImageResponse?, ImagePipeline.Error?) -> Void)? = nil) {
        let expectation = test.expectation(description: "Image request failed \(request)")
        pipeline.loadImage(with: request) { response, error in
            completion?(response, error)
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNil(response)
            XCTAssertNotNil(error)
            expectation.fulfill()
        }
    }
}

extension XCTestCase {
    func expectToFinishLoadingImage(with request: ImageRequest, options: ImageLoadingOptions = ImageLoadingOptions.shared, into imageView: ImageDisplayingView, completion: ImageTask.Completion? = nil) {
        let expectation = self.expectation(description: "Image loaded for \(request)")
        Nuke.loadImage(
            with: request,
            options: options,
            into: imageView,
            completion: { response, error in
                XCTAssertTrue(Thread.isMainThread)
                completion?(response, error)
                expectation.fulfill()
        })
    }

    func expectToLoadImage(with request: ImageRequest, options: ImageLoadingOptions = ImageLoadingOptions.shared, into imageView: ImageDisplayingView) {
        expectToFinishLoadingImage(with: request, options: options, into: imageView) { response, error in
            XCTAssertNotNil(response)
            XCTAssertNil(error)
        }
    }
}

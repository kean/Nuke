// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
import Foundation
import Nuke

extension XCTestCase {
    struct XCTestCasePipeline {
        let testCase: XCTestCase
        let pipeline: ImagePipeline

        func toLoadImage(with request: ImageRequest, _ completion: ((ImageResponse?, ImagePipeline.Error?) -> Void)? = nil) {
            let expectation = testCase.expectation(description: "Image loaded for request: \(request)")
            pipeline.loadImage(with: request) { response, error in
                completion?(response, error)
                XCTAssertNotNil(response)
                expectation.fulfill()
            }
        }
    }

    func expect(_ pipeline: ImagePipeline) -> XCTestCasePipeline {
        return XCTestCasePipeline(testCase: self, pipeline: pipeline)
    }
}

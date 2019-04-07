// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineConfigurationTests: XCTestCase {

    func testImageIsLoadedWithRateLimiterDisabled() {
        // Given
        let dataLoader = MockDataLoader()
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil

            $0.isRateLimiterEnabled = false
        }

        // When/Then
        expect(pipeline).toLoadImage(with: Test.request)
        wait()
    }
}   

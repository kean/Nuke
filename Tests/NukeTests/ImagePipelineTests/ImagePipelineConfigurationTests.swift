// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

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

    // MARK: DataCache

    func testWithDataCache() {
        let pipeline = ImagePipeline(configuration: .withDataCache)
        XCTAssertNotNil(pipeline.configuration.dataCache)
    }

    func testEnablingSignposts() {
        ImagePipeline.Configuration.isSignpostLoggingEnabled = false // Just padding
        ImagePipeline.Configuration.isSignpostLoggingEnabled = true
        ImagePipeline.Configuration.isSignpostLoggingEnabled = false
    }
}
